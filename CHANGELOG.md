# Changelog

## v0.4.0 — the community-hardened release

Everything v0.3.0-alpha carried, made to work right — the daedric-modes overhaul, a downed-state reliability patch, and a full author's-pen text pass.

- **The daedric-modes overhaul.** Sanguine, Sheogorath, Mephala, and Molag Bal each
  decide in their own voice. Every daemon decision is two-stage: the model weighs the
  room first, then picks subject, target, and act together — with a one-line motive
  ("why this subject, this target, right now"). Subjects and targets are cast from
  live pools (recent picks stay sticky, conversation partners get priority, proximity
  matters), with a Narrative / Random selection-method choice per mode in the MCM.
- **Reaction lanes.** Each daemon moment can land four ways at once: as in-scene
  narration, as the thoughts of nearby NPCs, as words aimed at you, or as your own
  thoughts — each lane on its own MCM toggle, Baka modes and pose modes alike.
- **Narratively robust.** Off-menu action paraphrases now always resolve to a legal
  action instead of silently doing nothing, and the daemon cadences re-arm in seconds
  after refusals and misses — no more silent dead air between moments. Arousal-keyed
  disposition prompts became suggestion sets the model picks from, not mechanical
  tiers.
- **The Acheron downed-state patch.** A community-reported soft-lock, closed: downed
  NPCs who aren't part of an active escalation now get up on their own about a minute
  after the fight ends; Help Up is always available as the release valve; if Acheron
  prematurely rescues someone twice, the third rescue is accepted; witness reactions
  collapse to one short post-combat window. A panic-reset control and a README
  troubleshooting guide ship with it.
- **Fixed: pose actions were silently failing.** Every LLM-driven pose action now
  fires as intended, and refusals leave named traces.
- **Community performance fold.** Four findings from a community source-read, all
  folded: no more deadline spin while combat blocks the daemon, no debug-string
  builds on hot paths with logging off, the FHU poll guard audited, and the tattoo
  observation walk yields frames on large pools.
- **Pose cues, re-penned.** Every pose cue reads as in-story prose — a solo line when
  no one is watching, a with-an-audience line when someone is — and stop lines read
  naturally ("…no longer holds the pose").
- **EmoTears fully optional.** Baka Interactions no longer carries EmoTears4NPCs as a
  hidden master: the load-order constraint is gone, and existing saves are safe.
- **The author's-pen text pass.** Trigger and action descriptions across the whole
  package re-voiced by hand, plus typo fixes throughout.
- **New optional decal source.** SLACS 2 + SCO (Cum Overlays) — an additional
  supported cum overlay decal, picked from the MCM's Decal Source dropdown when
  present.

Safe to install over v0.3.0-alpha (no save-format changes). One-time MCM note: the
GS-mode reaction-lane toggles reset to defaults once on this version (a settings-key
rename) — re-toggle them to taste if you had changed them.

## v0.3.0-alpha — the first full release (alpha state)

The full feature arc since v0.1.0: every module shipped — in an honest alpha state: tested in-house where possible, and looking to the community for testing, feedback, and shared logs to help diagnose issues.

- **The background-daemon era (Baka Interactions).** A background daemon (Mephala / Molag Bal modes) for the
  interaction core: Mephala and Molag Bal modes let dominant NPCs escalate on their
  own initiative, on cadences you set in the MCM (tick-interval sliders, 15–240 s),
  with seeded in-character thoughts — the same pattern as the pose daemon (Sanguine Mode).
- **GS Poses: one-pass pose picking.** The Sanguine Mode consideration prompt now reads a live
  pose catalog (per-category move lists with content descriptions) and answers with
  both the pose and the exact move in one pass. The old separate pose-picker decision
  step is retired. New Sanguine / Sheogorath narration modes (toggles + tick-interval
  sliders, default off), pose narration routes, and the pose gender policy dropdown
  (female-only / curated / all-poses).
- **Cum v2 — the full system.** Applied-cum awareness rebuilt: appliance-authority
  tracking (who or what applied it — creatures included), a decal-source selection
  dropdown, ambient follow-up cues on a configurable interval, per-source firing
  modes, and LLM disposition prompts for the aftermath — how each character deals
  with (or deals with having) the cum on them. Backed by the new service DLL's
  state store, so it survives save/load cleanly.
- **FHU v2 — the full system.** Fill Her Up inflation fully narrated: swelling on
  level-up, release on level-down, creature fills, read live from FHU's per-actor
  state; ambient inflation narration on by default (first cue fires the moment a
  band is entered, then on its own interval slider), and an OStim climax driver so
  OStim scenes drive their own inflation fills without any SexLab bridge.
- **SlaveTats v2.** Force Tattoo LLM lanes: a downed-gated Apply action and a Command
  action for "mark them / brand them" intent; ambient exposure rolls narrating who
  notices the marks a character is wearing; an in-game set-picker menu; ambient cue
  interval slider.
- **The prompt layer.** DeD now ships its own character-bio and context prompt
  fragments (cum, FHU, tattoos, spank state, nearby context) plus final-instruction
  disposition prompts, so the LLM always knows what the modules have done to (and
  around) each character.
- **The Acheron cue cap.** Downed-consequence cues are capped — one at the down
  moment and two in the following minute, then a per-character quiet gate — so a
  downed victim is narrated, not narrated at.
- **The story-voice pass.** Every narration cue, ambient text, and mode-narration
  prompt re-voiced from LLM-instruction language into in-story narration: cues
  describe what happens as it happens, and the model reacts as the character would.
- **The independence audit.** Every module is presence-gated and independently
  removable; FOMOD module toggles install or remove each module's files, the
  framework-carried content layers stay installed but inert, and nothing breaks in
  any combination.
- **Safety and polish.** An absolute child boundary (no module action of any kind
  ever targets an engine-marked child); category descriptions fixed so the LLM
  routes requests to the action that can serve them; the Execute action ships
  experimental behind a configurable ask-first gate; creature-struggle fixes and the
  Execute mention phrasing folded from Oldcustard's PR #2, with thanks.
- **Removed:** the vestigial `SNBaka_Pose` category — all pose actions render under
  the unified `SNGS_Pose` category.

## v0.1.0 — initial public version

Initial public version — the mod in active development. All features shipped
through this state are included; every module is pending its polish-and-
expansion pass.

What's in this state:

- **Baka Interactions** — paired NSFW interactions through the Interact power
  (affectionate, forced, and sexual actions), an escalation system with
  resistance/struggle/submit, capture, slavery, creature escalation, an
  execute-on-downed lane (EXPERIMENTAL), and a full MCM.
- **GS Poses** — solo posing: a PrismaUI pose-grid selector and LLM-driven
  contextual NPC posing (the Muse), sharing one flat pose category with
  Baka Interactions.
- **Cum** — SkyrimNet triggers when cum is applied (OCum ModEvent path and a
  SexLab end-of-scene proxy), with unified and per-source firing modes.
- **FHU** — Fill Her Up (Baka Edition) inflation level cues, keyed to its
  inflation ModEvents.
- **SlaveTats** — LLM-driven application of SlaveTats tattoo sets (spank
  marks, tears, and related sets) with NPC/player reactions.
- **Acheron Bridge** — downed-consequence SkyrimNet triggers bridged to
  Acheron's consequence system.

Every module above is functional but pending polish; versions will increment
as milestones ship.
