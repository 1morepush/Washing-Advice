"""Background removal.

The fixtures are synthetic — a solid shape on a solid or gently graded
backdrop. That is deliberate rather than a shortcut: it makes the correct
answer *known*, so the tests assert that a specific pixel is opaque and a
specific pixel is not, instead of eyeballing a photograph and calling it good.

What it does not prove is behaviour on a real garment on a real carpet. That
limitation is stated in the README rather than papered over here.
"""

from __future__ import annotations

import io

import pytest
from PIL import Image, ImageDraw

from app.services.images.cutout import BorderSampledRemover, CutoutError

WHITE = (245, 245, 242)
NAVY = (31, 42, 68)
OFF_WHITE = (252, 252, 250)


def photo(
    background: tuple[int, int, int],
    garment: tuple[int, int, int] | None,
    *,
    size: tuple[int, int] = (420, 560),
    graded: bool = False,
    fmt: str = "PNG",
) -> bytes:
    """A garment-shaped rectangle on a plain backdrop."""
    image = Image.new("RGB", size, background)

    if graded:
        pixels = image.load()
        assert pixels is not None
        for y in range(size[1]):
            factor = 1 - 0.2 * y / size[1]
            shaded = tuple(int(channel * factor) for channel in background)
            for x in range(size[0]):
                pixels[x, y] = shaded

    if garment is not None:
        width, height = size
        ImageDraw.Draw(image).rectangle(
            [width * 0.28, height * 0.22, width * 0.72, height * 0.80],
            fill=garment,
        )

    buffer = io.BytesIO()
    image.save(buffer, format=fmt)
    return buffer.getvalue()


def alpha_of(png: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(png))
    assert image.mode == "RGBA"
    return image.split()[-1]


@pytest.fixture
def remover() -> BorderSampledRemover:
    return BorderSampledRemover()


class TestSeparation:
    def test_the_garment_is_opaque_and_the_background_is_not(self, remover):
        result = remover.remove(photo(WHITE, NAVY))
        alpha = alpha_of(result.png)
        width, height = alpha.size

        assert alpha.getpixel((width // 2, height // 2)) == 255
        assert alpha.getpixel((2, 2)) == 0
        assert alpha.getpixel((width - 3, height - 3)) == 0

    def test_a_white_garment_on_a_white_background(self, remover):
        # The case that defeats a naive "drop everything near white" rule, and
        # the one a wardrobe hits constantly — white shirts photographed on a
        # bed. Distance from the *sampled* background is what makes it work.
        result = remover.remove(photo(WHITE, OFF_WHITE))
        alpha = alpha_of(result.png)
        width, height = alpha.size

        assert alpha.getpixel((width // 2, height // 2)) == 255
        assert alpha.getpixel((2, 2)) == 0

    def test_an_unevenly_lit_background(self, remover):
        # A backdrop lit from one side is two colours, and their average is a
        # third that appears nowhere in the frame. Clustering the border is
        # what stops both real shades reading as foreground.
        result = remover.remove(photo((200, 200, 200), (179, 50, 44), graded=True))
        assert result.is_plausible

        alpha = alpha_of(result.png)
        width, height = alpha.size
        assert alpha.getpixel((width // 2, height // 2)) == 255
        assert alpha.getpixel((2, 2)) == 0

    def test_the_output_keeps_the_source_dimensions(self, remover):
        result = remover.remove(photo(WHITE, NAVY, size=(640, 480)))
        assert (result.width, result.height) == (640, 480)
        assert Image.open(io.BytesIO(result.png)).size == (640, 480)

    def test_jpeg_input_is_accepted(self, remover):
        result = remover.remove(photo(WHITE, NAVY, fmt="JPEG"))
        assert result.is_plausible

    def test_the_same_photo_gives_the_same_cutout(self, remover):
        # The clustering is randomised, so the seed is pinned. Without this a
        # user could rescan an item and get a visibly different silhouette.
        source = photo(WHITE, NAVY)
        assert remover.remove(source).png == remover.remove(source).png


class TestRefusal:
    """Two different failures, and they are not interchangeable.

    *Nothing separated* raises: the image is uniform, so there is no subject
    and no mask to return. *Something separated but the wrong thing* returns a
    `Cutout` flagged implausible, because the caller may want the coverage
    figure to decide what to tell the user. Collapsing them would lose that.
    """

    def test_a_blank_image_has_no_subject_at_all(self, remover):
        with pytest.raises(CutoutError):
            remover.remove(photo(WHITE, None))

    def test_a_garment_filling_the_whole_frame_has_no_subject(self, remover):
        # Every pixel matches the border, so nothing is foreground. The user
        # needs to step back, and the endpoint says so.
        image = Image.new("RGB", (300, 300), NAVY)
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")

        with pytest.raises(CutoutError):
            remover.remove(buffer.getvalue())

    def test_a_speck_is_separated_but_reported_as_implausible(self, remover):
        # A separation that succeeded and found the wrong thing — a smudge on
        # the sheet rather than the shirt. Returning this as a cutout would
        # look like the feature worked.
        image = Image.new("RGB", (400, 400), WHITE)
        ImageDraw.Draw(image).rectangle([198, 198, 202, 202], fill=NAVY)
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")

        result = remover.remove(buffer.getvalue())
        assert result.coverage < 0.04
        assert not result.is_plausible

    def test_undecodable_bytes_raise_rather_than_crash(self, remover):
        with pytest.raises(CutoutError):
            remover.remove(b"this is not an image")


class TestCoverage:
    def test_coverage_matches_the_shape_drawn(self, remover):
        # The rectangle occupies 0.44 x 0.58 of the frame — about 25.5%. A
        # measured coverage near that is evidence the mask is the garment and
        # not merely *some* connected region of the right rough size.
        result = remover.remove(photo(WHITE, NAVY))
        assert result.coverage == pytest.approx(0.255, abs=0.03)
