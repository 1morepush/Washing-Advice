"""What the assistant is asked, and how the wardrobe is described to it.

The prompt spends most of its length on one failure, because one failure here
is far worse than the rest. Everywhere else in this service a wrong answer
costs a re-scan. Here a wrong answer is *followed* — somebody asks whether they
can put a jumper in the dryer, is told yes, and takes a felted jumper out of
it. The garment does not come back.

So the rules are about the boundary between what the app knows and what the
model is guessing:

- The wardrobe lines are facts the app holds. The care line on each is marked
  as read from a label or worked out from the fabric, and the answer has to
  keep that distinction rather than flattening both into "it says".
- A garment that is not in the list is not in the wardrobe as far as this
  conversation goes — unless the list was truncated, which is stated when it
  is, because "you do not own a white shirt" is a bad answer when eighty
  garments did not fit in the prompt.
- General laundry questions with no garment attached are fine and common —
  "how much detergent", "what does the triangle mean" — and get answered
  directly rather than deflected back to the wardrobe.

The other thing it spends length on is brevity. This is the answer to a quick
question, typed one-handed next to a machine. A screen of prose is a worse
answer than two sentences even when every word of it is right.
"""

from __future__ import annotations

from app.schemas.chat import ChatGarment, ChatRequest

CHAT_PROMPT = """You are the assistant built into a laundry and wardrobe app.
The person using it is asking you a quick question — often standing at a
machine, one-handed, wanting an answer rather than an essay.

Answer in one to four sentences. Give the answer first. Add a reason only when
it changes what they would do. No preamble, no restating the question, no
offers to help further, no bullet lists unless you are genuinely listing
several things.

WHAT YOU KNOW

Their wardrobe is listed below, one garment per line. Those are facts the app
holds — you are not guessing at them.

Each garment's care line is marked either LABEL (read off the sewn-in care
label) or GUESS (worked out by the app from what the garment is made of).

RULES YOU MUST NOT BREAK:

- Never present a GUESS as though it were the manufacturer's instruction. If
  the answer turns on it, say the app worked it out from the fabric and that
  the label is worth checking. Somebody who follows a confident guess into a
  tumble dryer does not get the garment back.
- Never contradict a LABEL care line. The label wins over anything you know
  about the fabric in general.
- When you are unsure and getting it wrong would damage a garment, say so and
  give the cautious answer. "Cold and hang it up" costs an afternoon; the other
  way round costs the garment.
- Do not invent garments. If they ask about something not in the list, say you
  cannot see it in their wardrobe rather than describing one.
- Answer general laundry questions — detergent, symbols, stains, machine
  settings — directly, whether or not any of their garments are involved. Not
  every question is about the wardrobe.
- You cannot change anything in the app: you cannot add garments, start a wash,
  or edit a care label. If they are asking for something to be done, say where
  in the app they can do it.

"""


def describe_garment(garment: ChatGarment) -> str:
    """One garment on one line.

    Terse on purpose. This is repeated for every garment on every message of
    every conversation, so a wasted clause is paid for hundreds of times.
    """
    parts = [garment.name, f"({garment.type}"]
    if garment.colors:
        parts[-1] += f", {', '.join(garment.colors)}"
    if garment.fabric:
        parts[-1] += f", {garment.fabric}"
    parts[-1] += ")"

    if garment.care:
        # The provenance rides on the same line as the instruction it
        # qualifies. Put in a separate column it would be read as decoration.
        source = "GUESS" if garment.care_is_guess else "LABEL"
        parts.append(f"— {source}: {garment.care}")
    if garment.state:
        parts.append(f"[{garment.state}]")

    return " ".join(parts)


def describe(request: ChatRequest) -> str:
    """The whole prompt: rules, wardrobe, then the conversation."""
    lines = [CHAT_PROMPT, "THEIR WARDROBE"]

    if not request.wardrobe:
        lines.append(
            "There is nothing in their wardrobe yet, or they have not shared "
            "it. Answer from general knowledge and do not refer to specific "
            "garments of theirs."
        )
    else:
        lines.extend(f"  • {describe_garment(garment)}" for garment in request.wardrobe)

        total = request.wardrobe_total
        if total is not None and total > len(request.wardrobe):
            # Said explicitly, because the alternative is a flat "you do not
            # own one" about a garment that simply did not fit.
            lines.append(
                f"\nThat is {len(request.wardrobe)} of their {total} garments — "
                "the rest did not fit here. If they ask about something you "
                "cannot see, say you cannot see all of their wardrobe rather "
                "than that they do not own it."
            )

    if request.history:
        lines.append("\nTHE CONVERSATION SO FAR")
        for turn in request.history:
            who = "They asked" if turn.role == "user" else "You answered"
            lines.append(f"  {who}: {turn.text}")

    lines.append(f"\nTHEIR QUESTION\n{request.question}")
    return "\n".join(lines)
