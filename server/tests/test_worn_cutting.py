"""Cutting a garment out of a photograph of the person wearing it.

The tests are synthetic on purpose, as the background-removal ones are: a known
scene, a known mask, and so a known answer. They assert that this pixel is
opaque and that one is not, which a photograph and an eyeballed result could not.

What that cannot show is how a real model's outlines look on a real person. The
module's job is to be right about the cases it can judge (empty, tiny, whole-box,
undecodable, speckled) and to say honestly when it fell back, and those are
exactly what is pinned here.
"""

from __future__ import annotations

import base64
import io
import math
from collections.abc import Callable

import numpy as np
import pytest
from PIL import Image, ImageDraw, PngImagePlugin

from app.schemas.scan import CutoutKind
from app.services.ai.base import ScanImage
from app.services.worn.cutting import (
    Cut,
    NormalisedBox,
    PhotoError,
    cut_garment,
    orient_photo,
    pixel_box,
)

SKY = (40, 60, 200)
RED = (220, 30, 30)

# A 200 x 300 photograph, and a box on it that is 160 x 240 pixels: from (20, 30)
# to (180, 270). Every mask below is drawn at the box's own size unless it says
# otherwise, so a mask pixel is a photograph pixel and the expected crop is
# arithmetic rather than a measurement.
PHOTO_SIZE = (200, 300)
BOX = NormalisedBox(0.1, 0.1, 0.9, 0.9)
BOX_ORIGIN = (20, 30)
BOX_SIZE = (160, 240)


def scene(size: tuple[int, int] = PHOTO_SIZE) -> Image.Image:
    """Blue everywhere except a red square at the top left of the box."""
    image = Image.new("RGB", size, SKY)
    ImageDraw.Draw(image).rectangle([20, 30, 100, 150], fill=RED)
    return image


def mask_image(
    draw: Callable[[ImageDraw.ImageDraw], None],
    size: tuple[int, int] = BOX_SIZE,
    *,
    mode: str = "L",
) -> Image.Image:
    image = Image.new(mode, size, 0)
    draw(ImageDraw.Draw(image))
    return image


def encode(image: Image.Image, *, prefix: bool = True) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    text = base64.b64encode(buffer.getvalue()).decode("ascii")
    return ("data:image/png;base64," + text) if prefix else text


def rect_mask(box: tuple[int, int, int, int], *, value: int = 255, **kwargs: object) -> str:
    """A mask that is one filled rectangle; `box` is inclusive-exclusive."""
    left, top, right, bottom = box
    return encode(
        mask_image(lambda d: d.rectangle([left, top, right - 1, bottom - 1], fill=value)),
        **kwargs,  # type: ignore[arg-type]
    )


def pixels_of(cut: Cut) -> np.ndarray:
    image = Image.open(io.BytesIO(cut.png))
    assert image.mode == "RGBA"
    return np.asarray(image)


# The garment used by most tests: 80 x 120 inside the 160 x 240 box. The cutout
# is the whole box, so it is 160 x 240 whatever the garment's size.
CORE = (40, 60, 120, 180)


class TestTheBox:
    @pytest.mark.parametrize(
        "box",
        [
            NormalisedBox(0.3, 0.3, 0.3, 0.6),  # no width
            NormalisedBox(0.3, 0.3, 0.6, 0.3),  # no height
            NormalisedBox(0.6, 0.3, 0.3, 0.6),  # backwards in x
            NormalisedBox(0.3, 0.6, 0.6, 0.3),  # backwards in y
            NormalisedBox(1.2, 0.1, 1.5, 0.5),  # entirely off the right
            NormalisedBox(-0.5, 0.1, -0.1, 0.5),  # entirely off the left
            NormalisedBox(0.1, 1.0, 0.5, 1.4),  # entirely off the bottom
            NormalisedBox(0.1, 0.1, 0.11, 0.11),  # two pixels: a point, not a garment
            NormalisedBox(math.nan, 0.1, 0.5, 0.5),
            NormalisedBox(0.1, 0.1, math.inf, 0.5),
        ],
    )
    def test_a_nonsense_box_is_nothing(self, box: NormalisedBox) -> None:
        assert pixel_box(box, PHOTO_SIZE) is None
        assert cut_garment(scene(), box, None) is None
        assert cut_garment(scene(), box, rect_mask(CORE)) is None

    def test_a_good_box_is_the_pixels_it_covers(self) -> None:
        pixels = pixel_box(BOX, PHOTO_SIZE)

        assert pixels is not None
        assert (pixels.left, pixels.top, pixels.right, pixels.bottom) == (20, 30, 180, 270)
        assert (pixels.width, pixels.height) == BOX_SIZE

    def test_a_box_hanging_over_the_edge_is_cut_where_it_is_visible(self) -> None:
        cut = cut_garment(scene(), NormalisedBox(0.5, 0.5, 1.4, 1.4), None)

        assert cut is not None
        assert cut.box == NormalisedBox(0.5, 0.5, 1.0, 1.0)
        assert (cut.width, cut.height) == (100, 150)

    def test_the_box_in_the_result_is_the_one_that_was_cut(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        assert cut.box == BOX

    def test_a_float_a_hair_over_does_not_cost_a_pixel(self) -> None:
        # 0.3 * 10 is 3.0000000000000004. Taken at face value its ceil is 4, a
        # whole pixel more than the box covers.
        pixels = pixel_box(NormalisedBox(0.3, 0.3, 0.9, 0.9), (10, 10))

        assert pixels is not None
        assert (pixels.left, pixels.top, pixels.right, pixels.bottom) == (3, 3, 9, 9)

    def test_gemini_boxes_are_y_first_and_out_of_a_thousand(self) -> None:
        box = NormalisedBox.from_box_2d([100, 200, 900, 800])

        assert box == NormalisedBox(left=0.2, top=0.1, right=0.8, bottom=0.9)


class TestAnOutlineThatPassesVetting:
    def test_is_used_and_says_so(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE

    def test_the_picture_is_rgba(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        assert Image.open(io.BytesIO(cut.png)).mode == "RGBA"

    def test_is_the_whole_box_and_not_trimmed_to_the_mask(self) -> None:
        # The app keeps an opaque crop of the same box, and the editor's "add
        # back" brush restores from it: the two must be one frame.
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        assert (cut.width, cut.height) == BOX_SIZE
        assert pixels_of(cut).shape[:2] == (240, 160)

    def test_pixel_for_pixel_the_cutout_lines_up_with_the_box_crop(self) -> None:
        # Where the cutout is opaque it is the photograph's pixel at the same
        # place in the box: the property "add back" depends on.
        photo = scene()
        cut = cut_garment(photo, BOX, rect_mask(CORE))

        assert cut is not None
        rgba = pixels_of(cut)
        crop = np.asarray(photo.crop((20, 30, 180, 270)))
        opaque = rgba[..., 3] == 255
        assert opaque.sum() > 0
        assert (rgba[opaque][:, :3] == crop[opaque]).all()

    def test_the_garment_is_opaque_and_the_picture_is_the_photographs(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        rgba = pixels_of(cut)
        # The cutout starts at (20, 30) in the photograph. The mask covers
        # photograph x 60..140, y 90..210; (75, 110) is well inside it and inside
        # the red square.
        assert tuple(rgba[110 - 30, 75 - 20]) == (*RED, 255)
        # (120, 190) is inside the mask and outside the red square.
        assert tuple(rgba[190 - 30, 120 - 20]) == (*SKY, 255)

    def test_is_transparent_outside_the_mask(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        alpha = pixels_of(cut)[..., 3]
        # The box's four corners and the middle of every side.
        for y, x in [
            (0, 0),
            (0, 159),
            (239, 0),
            (239, 159),
            (0, 80),
            (239, 80),
            (120, 0),
            (120, 159),
        ]:
            assert alpha[y, x] == 0, (y, x)

    def test_leaves_nothing_behind_a_transparent_pixel(self) -> None:
        # A cutout is kept and shown small; whatever stood beside the garment
        # must not be recoverable from the pixels nobody can see.
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        rgba = pixels_of(cut)
        hidden = rgba[rgba[..., 3] == 0]
        assert len(hidden) > 0
        assert not hidden[:, :3].any()

    def test_the_edge_is_feathered(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        alpha = pixels_of(cut)[..., 3]
        assert ((alpha > 0) & (alpha < 255)).any(), "a hard edge composites with a jagged line"

    def test_the_soft_edge_carries_garment_colour_not_the_background(self) -> None:
        # A red garment on a blue background. The feathered band is partly
        # opaque, so whatever colour sits under it shows: it must be the
        # garment's, never the neighbour's.
        photo = Image.new("RGB", PHOTO_SIZE, SKY)
        ImageDraw.Draw(photo).rectangle([60, 90, 139, 209], fill=RED)

        cut = cut_garment(photo, BOX, rect_mask(CORE))

        assert cut is not None
        rgba = pixels_of(cut)
        solid = np.zeros(rgba.shape[:2], dtype=bool)
        solid[60:180, 40:120] = True  # CORE, in box coordinates

        band = ~solid & (rgba[..., 3] > 0)
        assert band.sum() > 0, "there is a soft edge to look at"
        assert (rgba[band][:, :3] == RED).all()
        # And nowhere does the background's blue survive under any opacity.
        visible = rgba[rgba[..., 3] > 0][:, :3]
        assert not (visible == SKY).all(axis=1).any()

    def test_the_soft_edge_keeps_the_hidden_pixels_cleared(self) -> None:
        photo = Image.new("RGB", PHOTO_SIZE, SKY)
        ImageDraw.Draw(photo).rectangle([60, 90, 139, 209], fill=RED)

        cut = cut_garment(photo, BOX, rect_mask(CORE))

        assert cut is not None
        rgba = pixels_of(cut)
        assert not rgba[rgba[..., 3] == 0][:, :3].any()

    def test_is_deterministic(self) -> None:
        first = cut_garment(scene(), BOX, rect_mask(CORE))
        second = cut_garment(scene(), BOX, rect_mask(CORE))

        assert first is not None and second is not None
        assert first.png == second.png

    @pytest.mark.parametrize("prefix", [True, False])
    def test_the_data_prefix_is_optional(self, prefix: bool) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE, prefix=prefix))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE

    def test_a_prefix_in_capitals_and_a_mask_with_line_breaks_are_tolerated(self) -> None:
        plain = rect_mask(CORE, prefix=False)
        wrapped = "\n".join(plain[i : i + 40] for i in range(0, len(plain), 40))

        cut = cut_garment(scene(), BOX, "DATA:IMAGE/PNG;BASE64," + wrapped)

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE

    def test_missing_padding_and_the_url_safe_alphabet_are_tolerated(self) -> None:
        plain = rect_mask(CORE, prefix=False)
        mangled = plain.rstrip("=").replace("+", "-").replace("/", "_")

        cut = cut_garment(scene(), BOX, mangled)

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE

    def test_a_mask_at_any_resolution_is_resized_to_the_box(self) -> None:
        # Gemini sizes a mask to its box in theory and to whatever it likes in
        # practice. Half the resolution, same rectangle in proportion.
        small = mask_image(lambda d: d.rectangle([20, 30, 59, 89], fill=255), (80, 120))

        cut = cut_garment(scene(), BOX, encode(small))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        assert (cut.width, cut.height) == BOX_SIZE

    def test_a_mask_in_another_mode_is_read_as_greyscale(self) -> None:
        for mode, fill in (("RGB", (255, 255, 255)), ("RGBA", (255, 255, 255, 255)), ("1", 1)):
            image = mask_image(lambda d, f=fill: d.rectangle([40, 60, 119, 179], fill=f), mode=mode)  # type: ignore[misc]

            cut = cut_garment(scene(), BOX, encode(image))

            assert cut is not None, mode
            assert cut.kind is CutoutKind.OUTLINE, mode

    def test_a_probability_map_is_thresholded_at_half(self) -> None:
        # A confident core (200) with a faint halo (100) around it: only the core
        # is the garment, so the halo stays transparent.
        image = mask_image(
            lambda d: (
                d.rectangle([20, 30, 139, 209], fill=100),
                d.rectangle([40, 60, 119, 179], fill=200),
            )
        )

        cut = cut_garment(scene(), BOX, encode(image))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        alpha = pixels_of(cut)[..., 3]
        assert alpha[120, 80] == 255  # the core
        assert alpha[40, 30] == 0  # inside the halo, outside the core

    def test_a_garment_touching_the_box_edge_is_the_same_frame(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask((0, 0, 100, 150)))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        assert (cut.width, cut.height) == BOX_SIZE

    def test_is_capped_to_the_display_size(self) -> None:
        photo = Image.new("RGB", (3000, 4000), SKY)
        mask = mask_image(lambda d: d.rectangle([100, 100, 2300, 3100], fill=255), (2400, 3200))

        cut = cut_garment(photo, NormalisedBox(0.1, 0.1, 0.9, 0.9), encode(mask))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        assert max(cut.width, cut.height) == 768
        assert pixels_of(cut).shape[:2] == (cut.height, cut.width)

    def test_a_small_photograph_is_never_upscaled(self) -> None:
        cut = cut_garment(scene(), BOX, rect_mask(CORE))

        assert cut is not None
        assert cut.width <= BOX_SIZE[0] and cut.height <= BOX_SIZE[1]


class TestRegions:
    def test_a_pair_of_shoes_is_two_regions_and_both_are_kept(self) -> None:
        # Two shapes with a gap between them. Keeping only the largest, as the
        # flat-lay cutout rightly does for one garment, would lose a shoe.
        mask = encode(
            mask_image(
                lambda d: (
                    d.ellipse([5, 80, 65, 160], fill=255),
                    d.ellipse([95, 80, 155, 160], fill=255),
                )
            )
        )

        cut = cut_garment(scene(), BOX, mask)

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        alpha = pixels_of(cut)[..., 3]
        # The frame spans both shoes, not one.
        assert cut.width == BOX_SIZE[0]
        # Each shoe's centre is opaque, and the gap between them is not.
        row = cut.height // 2
        assert alpha[row, 30] == 255
        assert alpha[row, cut.width // 2] == 0
        assert alpha[row, cut.width - 36] == 255

    def test_speckle_is_dropped(self) -> None:
        speck = (150, 220, 153, 223)  # 3 x 3, far from the garment.
        image = mask_image(
            lambda d: (
                d.rectangle([40, 60, 119, 179], fill=255),
                d.rectangle([speck[0], speck[1], speck[2] - 1, speck[3] - 1], fill=255),
            )
        )

        cut = cut_garment(scene(), BOX, encode(image))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        alpha = pixels_of(cut)[..., 3]
        assert alpha[220 - 0, 150] == 0  # the speck, in box coordinates
        assert alpha[120, 80] == 255

    def test_a_small_hole_in_the_garment_is_filled(self) -> None:
        image = mask_image(
            lambda d: (
                d.rectangle([40, 60, 119, 179], fill=255),
                d.rectangle([77, 117, 82, 122], fill=0),  # 6 x 6
            )
        )

        cut = cut_garment(scene(), BOX, encode(image))

        assert cut is not None
        alpha = pixels_of(cut)[..., 3]
        # Box (77..82, 117..122) is the hole.
        assert alpha[120, 80] == 255

    def test_a_large_hole_is_a_real_one_and_stays_open(self) -> None:
        # The gap between a bag's strap and its body is not noise.
        image = mask_image(
            lambda d: (
                d.rectangle([40, 60, 119, 179], fill=255),
                d.rectangle([60, 100, 99, 139], fill=0),  # 40 x 40, over 2% of the box
            )
        )

        cut = cut_garment(scene(), BOX, encode(image))

        assert cut is not None
        assert cut.kind is CutoutKind.OUTLINE
        alpha = pixels_of(cut)[..., 3]
        assert alpha[120, 80] == 0


class TestAMaskThatFallsBackToTheBox:
    """Every way a mask can be unusable ends in the same place: a plain crop."""

    def assert_box_crop(self, cut: Cut | None) -> None:
        assert cut is not None
        assert cut.kind is CutoutKind.BOX
        assert (cut.width, cut.height) == BOX_SIZE
        rgba = pixels_of(cut)
        # Opaque everywhere: the background is in the picture, and an alpha
        # channel saying otherwise would make it look cut out.
        assert (rgba[..., 3] == 255).all()
        # And it is the box's own pixels: the red square's corner at (20, 30).
        assert tuple(rgba[0, 0, :3]) == RED
        assert tuple(rgba[-1, -1, :3]) == SKY

    def test_no_mask_at_all(self) -> None:
        self.assert_box_crop(cut_garment(scene(), BOX, None))

    @pytest.mark.parametrize(
        "mask",
        [
            "",
            "   ",
            "not base64 at all !!!",
            "data:image/png;base64",  # no comma
            "data:image/png;base64,",
            "data:image/png;base64,%%%%",
            base64.b64encode(b"this is text, not a picture").decode(),
            base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 20).decode(),  # a header and no image
            "A" * 7_000_000,  # larger than any mask is allowed to be
        ],
    )
    def test_an_undecodable_mask(self, mask: str) -> None:
        self.assert_box_crop(cut_garment(scene(), BOX, mask))

    def test_a_truncated_png(self) -> None:
        whole = base64.b64decode(rect_mask(CORE, prefix=False))

        truncated = base64.b64encode(whole[: len(whole) // 2]).decode()

        self.assert_box_crop(cut_garment(scene(), BOX, truncated))

    def test_a_mask_that_is_all_dark(self) -> None:
        self.assert_box_crop(cut_garment(scene(), BOX, encode(mask_image(lambda d: None))))

    def test_a_mask_that_is_only_faint(self) -> None:
        # Everything under the threshold is "not the garment", so this is empty.
        self.assert_box_crop(cut_garment(scene(), BOX, rect_mask(CORE, value=90)))

    def test_a_mask_that_covers_the_whole_box(self) -> None:
        # No outline at all: the box, restated.
        full = mask_image(lambda d: d.rectangle([0, 0, 159, 239], fill=255))

        self.assert_box_crop(cut_garment(scene(), BOX, encode(full)))

    def test_a_mask_that_covers_almost_the_whole_box(self) -> None:
        # 99% of the box: two thin dark strips on one edge.
        almost = mask_image(
            lambda d: (d.rectangle([0, 0, 159, 239], fill=255), d.rectangle([0, 0, 159, 1], fill=0))
        )

        self.assert_box_crop(cut_garment(scene(), BOX, encode(almost)))

    @pytest.mark.parametrize(
        ("size", "believed"),
        [
            ((16, 15), False),  # 0.6% of the box
            ((27, 28), False),  # 1.97%
            ((28, 28), True),  # 2.04%
        ],
    )
    def test_a_mask_is_too_small_to_be_a_garment_under_two_percent(
        self, size: tuple[int, int], believed: bool
    ) -> None:
        mask = rect_mask((50, 50, 50 + size[0], 50 + size[1]))

        cut = cut_garment(scene(), BOX, mask)

        assert cut is not None
        assert (cut.kind is CutoutKind.OUTLINE) is believed

    def test_a_mask_of_scattered_specks_whose_total_looks_plausible(self) -> None:
        # Fifty 3-pixel specks: 150 px of 38400, which is under 2% as well; use
        # enough to pass the first test by their sum, and fail the second once
        # the speckle is cleaned away.
        def specks(d: ImageDraw.ImageDraw) -> None:
            for row in range(10):
                for column in range(10):
                    x, y = 8 + column * 14, 8 + row * 22
                    d.rectangle([x, y, x + 5, y + 5], fill=255)  # 36 px each, 3600 px: 9.4%

        self.assert_box_crop(cut_garment(scene(), BOX, encode(mask_image(specks))))

    def test_a_good_box_with_a_bad_mask_is_still_a_detection(self) -> None:
        # The whole point of the fallback: the garment is found, only its
        # outline is not trusted.
        cut = cut_garment(scene(), BOX, "garbage")

        assert cut is not None
        assert cut.box == BOX


class TestOrientation:
    """A sideways photograph is cut the way the model saw it: upright."""

    @staticmethod
    def sideways_jpeg(orientation: int, upright: Image.Image) -> bytes:
        """What a phone stores: turned pixels and a tag that turns them back."""
        # EXIF 6 means "rotate 90 degrees clockwise to display". The stored
        # picture is therefore the upright one rotated 90 degrees the other way.
        stored = {
            1: upright,
            3: upright.rotate(180, expand=True),
            6: upright.rotate(90, expand=True),
            8: upright.rotate(-90, expand=True),
        }[orientation]
        exif = Image.Exif()
        exif[0x0112] = orientation
        buffer = io.BytesIO()
        stored.save(buffer, format="JPEG", quality=95, exif=exif)
        return buffer.getvalue()

    @staticmethod
    def upright_scene() -> Image.Image:
        """Portrait, with a red block at the top left and a green one at the bottom right."""
        image = Image.new("RGB", (100, 160), (255, 255, 255))
        draw = ImageDraw.Draw(image)
        draw.rectangle([0, 0, 39, 59], fill=(255, 0, 0))
        draw.rectangle([60, 100, 99, 159], fill=(0, 160, 0))
        return image

    @pytest.mark.parametrize("orientation", [3, 6, 8])
    def test_the_photograph_is_stood_upright(self, orientation: int) -> None:
        data = self.sideways_jpeg(orientation, self.upright_scene())

        oriented = orient_photo(ScanImage(data=data, mime_type="image/jpeg"))

        assert oriented.image.size == (100, 160)
        assert oriented.image.mode == "RGB"
        red = oriented.image.getpixel((10, 10))
        green = oriented.image.getpixel((90, 150))
        assert isinstance(red, tuple) and red[0] > 200 and red[1] < 60
        assert isinstance(green, tuple) and green[1] > 120 and green[0] < 60

    @pytest.mark.parametrize("orientation", [3, 6, 8])
    def test_the_model_is_shown_the_same_upright_picture(self, orientation: int) -> None:
        data = self.sideways_jpeg(orientation, self.upright_scene())

        oriented = orient_photo(ScanImage(data=data, mime_type="image/jpeg"))

        shown = Image.open(io.BytesIO(oriented.for_model.data))
        assert shown.size == oriented.image.size
        # Re-encoded upright, so there is no tag left for a decoder to apply a
        # second time.
        assert shown.getexif().get(0x0112, 1) == 1
        assert oriented.for_model.mime_type == "image/jpeg"

    @pytest.mark.parametrize("orientation", [3, 6, 8])
    def test_a_box_on_the_upright_picture_cuts_the_right_pixels(self, orientation: int) -> None:
        data = self.sideways_jpeg(orientation, self.upright_scene())
        oriented = orient_photo(ScanImage(data=data, mime_type="image/jpeg"))

        # The red block, as an upright-picture box. Cut from the sideways stored
        # pixels this would be a different part of the photograph.
        cut = cut_garment(oriented.image, NormalisedBox(0.0, 0.0, 0.4, 0.375), None)

        assert cut is not None
        centre = pixels_of(cut)[cut.height // 2, cut.width // 2]
        assert centre[0] > 200 and centre[1] < 60 and centre[2] < 60

    def test_an_upright_photograph_is_sent_untouched(self) -> None:
        # Not re-encoded: an ordinary shot should not pay a generation of JPEG
        # loss for a rotation it does not need.
        original = ScanImage(
            data=self.sideways_jpeg(1, self.upright_scene()), mime_type="image/jpeg"
        )

        assert orient_photo(original).for_model is original

    def test_a_photograph_with_no_orientation_tag_is_sent_untouched(self) -> None:
        buffer = io.BytesIO()
        self.upright_scene().save(buffer, format="PNG")
        original = ScanImage(data=buffer.getvalue(), mime_type="image/png")

        oriented = orient_photo(original)

        assert oriented.for_model is original
        assert oriented.image.size == (100, 160)

    def test_a_photograph_that_will_not_open_is_an_error_not_a_crash(self) -> None:
        with pytest.raises(PhotoError):
            orient_photo(ScanImage(data=b"\xff\xd8\xff not really a jpeg", mime_type="image/jpeg"))

    def test_transparency_in_the_photograph_does_not_leak_into_the_cut(self) -> None:
        buffer = io.BytesIO()
        Image.new("RGBA", (100, 100), (255, 0, 0, 0)).save(buffer, format="PNG")

        oriented = orient_photo(ScanImage(data=buffer.getvalue(), mime_type="image/png"))

        assert oriented.image.mode == "RGB"


class TestAPhotographThatIsTooLarge:
    def test_one_over_the_pixel_cap_is_refused_before_it_is_decoded(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # A solid PNG compresses to almost nothing, which is the point: it is
        # tiny to send and enormous to decode.
        buffer = io.BytesIO()
        Image.new("L", (7000, 6000), 0).save(buffer, format="PNG")  # 42 MP
        assert len(buffer.getvalue()) < 200_000

        def never(self: Image.Image) -> None:
            raise AssertionError("decoded a photograph that should have been refused")

        monkeypatch.setattr(PngImagePlugin.PngImageFile, "load", never)

        with pytest.raises(PhotoError, match="too large"):
            orient_photo(ScanImage(data=buffer.getvalue(), mime_type="image/png"))

    def test_one_under_the_cap_is_accepted(self) -> None:
        buffer = io.BytesIO()
        Image.new("RGB", (6000, 6000), (10, 20, 30)).save(buffer, format="PNG")  # 36 MP

        oriented = orient_photo(ScanImage(data=buffer.getvalue(), mime_type="image/png"))

        assert oriented.image.size == (6000, 6000)

    def test_a_jpeg_over_the_cap_is_refused_too(self) -> None:
        buffer = io.BytesIO()
        Image.new("RGB", (8000, 6000), (10, 20, 30)).save(buffer, format="JPEG")  # 48 MP

        with pytest.raises(PhotoError, match="too large"):
            orient_photo(ScanImage(data=buffer.getvalue(), mime_type="image/jpeg"))

    def test_an_ordinary_jpeg_is_not_shrunk_by_the_draft_mode(self) -> None:
        buffer = io.BytesIO()
        Image.new("RGB", (4000, 3000), (10, 20, 30)).save(buffer, format="JPEG")

        oriented = orient_photo(ScanImage(data=buffer.getvalue(), mime_type="image/jpeg"))

        assert oriented.image.size == (4000, 3000)
