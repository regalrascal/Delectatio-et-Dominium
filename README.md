# Delectatio et Dominium

<p align="center">
  <img src="Delectatio_et_Dominium_Cover.jpg" alt="Delectatio et Dominium" width="480">
</p>

**Bedroom drama for SkyrimNet.** DeD v0.3.0-alpha — the first full release: every module
shipped, polished, and dogfood-tested.

Delectatio et Dominium (DeD) is a **modular SkyrimNet integration framework** for adult
Skyrim modding. Instead of one monolithic adult mod, DeD is a set of modules that hook
auxiliary and niche adult mods into [SkyrimNet](https://github.com/goncalo22/SkyrimNet) —
so the LLM driving your NPCs can perceive and act on what those mods are actually doing
to (and around) the player and other characters. The structural idea: a modular framework
that can support a number of mods while requiring as few as one of them. Each module is a
separable file-set with a FOMOD installer option, so you install only what you use.

Everything the LLM narrates is written in-story: cues and ambient narration describe what
is happening as it happens — the model reacts as the character would, never breaking the
scene to explain itself. Nothing fires at random; every interaction and pose is decided by
SkyrimNet's model, in context, from the characters' personalities. Master toggles, an
intensity slider, and per-module settings let you dial everything back.

> ⚠️ **Adult content (18+).** This mod adds non-consensual / NSFW interactions and other
> extreme roleplay themes. See the disclaimer below before installing.

---

## Modules

| Module | What it does |
| --- | --- |
| **Baka Interactions** | The interaction core: paired NSFW actions through the Interact power (affectionate, forced, and sexual actions targeted at any NPC, a downed victim, a hostile creature, or yourself), an escalation system (resist / struggle / submit / call for help), capture, tie-up, slavery, creature escalation, and a **Muse-style background daemon** — Mephala and Molag Bal modes that let dominant NPCs escalate on their own initiative, on cadences you set. |
| **GS Poses** | Solo posing: a PrismaUI pose-grid selector (19 high-quality pose categories on the player or any targeted NPC), the **Muse** background daemon that puts nearby NPCs into mood-fitting poses (with **Overdrive Mode** to raise ambient intensity), a **pose gender policy** (female-only / curated / all-poses), and optional **Sanguine / Sheogorath narration modes** with their own cadence sliders. Every pose pick is grounded by an LLM consideration prompt that picks both the pose and the exact move in one pass, from live scene context. |
| **Cum (v2)** | Full awareness of applied cum: SkyrimNet triggers when cum is applied (the OCum ModEvent path, plus a SexLab end-of-scene proxy), with unified and per-source firing modes, a decal-source selection dropdown, appliance-authority tracking (who or what applied it — creatures included), ambient follow-up cues on an interval you set, and LLM disposition of the aftermath (how each character deals with, or deals with having, the cum on them). |
| **FHU (v2)** | [Fill Her Up — Baka Edition](https://www.loverslab.com/) inflation fully narrated: level-up swelling, level-down release, creature fills, read live from FHU's own per-actor state; **ambient inflation narration on by default** (first cue fires the moment a band is entered, then on its own interval), and an **OStim climax driver** so OStim scenes drive their own inflation fills even without a SexLab bridge. |
| **SlaveTats (v2)** | LLM-driven degradation tattoos: spank marks, tears, drool, and related sets applied with NPC/player reactions, an in-game set-picker menu, **Force Tattoo LLM lanes** (a downed-gated Apply action; a Command action for "mark them / brand them" intent), and **ambient exposure** — ambient rolls narrating who notices the marks a character is wearing, and how they feel about being seen. |
| **Acheron Bridge** | Downed-consequence SkyrimNet triggers bridged to [Acheron](https://www.loverslab.com/)'s consequence system: the downed handoff, consequence cues in a capped cadence (one at the down moment, a couple in the following minute, then quiet), and the Downed State MCM page. |
| **DeD Service** | The always-installed service DLL behind the modules: a central state store with save-game-safe persistence, a single shared scheduler for every ambient pass, and the event pump the modules talk through. |

**Independence model:** every module is presence-gated and independently removable. The
FOMOD's module toggles install or remove each module's files (esp, DLL, content pack,
assets); the content layers the framework carries stay installed but inert, so nothing
breaks in any combination — run one module, run them all, or run none.

## Requirements

### Core (always required)

- [Skyrim Special Edition / Anniversary Edition](https://store.steampowered.com/app/489830/The_Elder_Scrolls_V_Skyrim_Special_Edition/) — 1.5.97 or 1.6.x (both verified in-house)
- [SKSE64](https://skse.silverlock.org/) matching your runtime
- [SkyrimNet](https://goncalo22.github.io/SkyrimNet-GamePlugin/) (the LLM framework this mod integrates with — required; Beta 25 / 0.25.x or later)
- [SkyUI / MCM](https://www.nexusmods.com/skyrimspecialedition/mods/12604) — the configuration menu
- [PapyrusUtil](https://www.nexusmods.com/skyrimspecialedition/mods/13044) — settings storage
- [PrismaUI](https://www.nexusmods.com/skyrimspecialedition/mods/134660) — the interaction, pose, and tattoo menus
- [Baka Motion Data Pack](https://www.loverslab.com/files/file/26992-baka-motion-data-pack/) — the paired interaction animations; run **Pandora / FNIS / Nemesis** after installing
- **A safety line, not a requirement:** no module action of any kind ever targets an
  engine-marked child, anywhere in the framework — an absolute boundary, no exceptions,
  independent of any toggle.

**Game version compatibility:** SE 1.5.97 and AE 1.6.x are verified in-house. The DLLs
follow the Address-Library architecture, so loading on the 1.7.104 runtime with matching
SKSE (2.3.1) is expected to work — but has not been verified in-house. Feedback from 1.7
users is welcome.

### Adult animation framework (at least one)

- [SexLab Framework](https://www.loverslab.com/files/file/5911-sexlab-framework-se/) and/or **OSex / OStim** — at least one is needed for paired scenes to start (both are supported simultaneously; the MCM picks Auto). Without one, escalation simply won't start a scene — nothing breaks.

### Per-module (only for the modules you install)

- [GSPoses by Gunslicer](https://www.loverslab.com/files/file/28221-gsposes/) — the GS solo-pose animations (GS Poses)
- [Fill Her Up — Baka Edition](https://www.loverslab.com/) — inflation (FHU)
- [SlaveTats](https://www.loverslab.com/) (includes JContainers) — degradation tattoos (SlaveTats)
- [Acheron](https://www.loverslab.com/) — the downed-consequence bridge (Acheron Bridge)
- [OCum](https://www.loverslab.com/) — applied-cum events (Cum; the SexLab end-of-scene proxy also works without OCum)

Each module is inert without its prerequisite — it greys out in the MCM and does nothing
rather than breaking.

### Soft (strongly recommended)

- **An arousal framework — pick ONE:** OSL Aroused - Arousal Reborn, or SL Aroused (NG). Arousal-aware reactions key on it; if both are present the runtime resolves Aroused Reborn first, then SL Aroused, else runs neutral. (Reborn bundles its own copy of SexLabAroused.esm, so seeing that esm does not by itself mean SL Aroused NG is installed.)
- [Flash Games – Struggling QTE](https://www.nexusmods.com/skyrimspecialedition/mods/121909) — blocking-based QTE for grab/choke holds
- [Dynamic Feminine Female Modesty Animations OAR](https://www.nexusmods.com/skyrimspecialedition/mods/104374) — cover-self reaction (no animations are bundled for this)
- [Additional Expressions Project](https://www.nexusmods.com/skyrimspecialedition/mods/72337) — facial-expression morph values (the values are baked in; the mod itself isn't required at runtime)
- [EmoTears4NPCs / EmoTears](https://www.nexusmods.com/skyrimspecialedition/mods/122296) — animated tears
- [SeverActions – SkyrimNet Action Pack](https://www.loverslab.com/files/file/34312-severactions-skyrimnet-action-pack/) — enriches the LLM's downed/capture options; DeD's downed cues invite these outcomes

### Flavor (optional, each degrades gracefully if absent)

- [OCreatures Revived](https://www.loverslab.com/files/file/49059-ocreatures-revived/) — for creature escalation to produce a scene (you also need creature animation packs covering the creature types)
- [Simple Slavery Plus Plus (SS++)](https://www.loverslab.com/files/file/13674-simple-slavery-plus-plus/) — required for the `SellToSlavery` action (defeated **player** only)
- [Follower Slavery Mod (FSM)](https://www.loverslab.com/files/file/30956-follower-slavery-mod-/) — required for the `EnslaveFollower` action (OFF by default)

## Installation

Install with a mod manager (Mod Organizer 2 recommended): the FOMOD wizard walks you
through the modules and installs only the file-sets you pick.

1. Install and configure the requirements above (SkyrimNet first).
2. Install DeD with MO2 — choose your modules in the wizard. If you were running the
   original SkyrimNet Baka Integration, Animations GS, or Acheron Integration separately,
   remove them first — DeD replaces all three.
3. Run **Pandora / FNIS / Nemesis** so the paired animations register.
4. Launch via SKSE. Each installed module gets a configuration page in the
   **Delectatio et Dominium** MCM.
5. In SkyrimNet's dashboard, verify the `regalrascal.*` / `around906.*` content packs are
   listed, then reload its config (or restart).

Manual install: copy the folders from the archive into your `Data` directory and enable
the ESPs for your chosen modules — but the wizard is the supported path.

## The MCM

Configuration lives in one **Delectatio et Dominium** MCM, split into pages: **Settings**
(master toggles, expression intensity, uninstall/panic reset), **Baka Interactions**
(interactions, escalation, capture, creatures, the Mephala / Molag Bal daemon cadences),
**Cum Effects**, **Fill Her Up**, **Acheron** (Downed State), **SlaveTats**, and
**GS Poses**. Highlights of what you can dial:

- **Master enable + per-module toggles** — every module can be switched off; each greys
  out when its prerequisite mod is absent
- **Expression intensity slider** — how strongly faces react (0.0–1.0)
- **Ambient Cue Interval sliders** (Cum, FHU, SlaveTats) — how often ambient follow-up
  narration fires (15–240 s / 60–1800 s)
- **Daemon cadence sliders** — Mephala / Molag Bal tick intervals, Sanguine / Sheogorath
  tick intervals (15–240 s)
- **Mode-narration toggles** — Sanguine / Sheogorath mode narration (default off), pose
  narration routes on the GS Poses page
- **Pose gender policy** — female-only / curated / all-poses dropdown
- **Decal source selection** dropdown (Cum)
- **Execute gate** — how the Execute action may be used (unlimited / companions ask /
  always ask)
- **Arousal chain** — neutral when no arousal framework is present; otherwise resolves
  Aroused Reborn → SL Aroused

## Honest-state notes

**EXPERIMENTAL — the Execute action.** The execute-on-downed-victim lane (Baka
Interactions) ships **experimental**: it is heavily guarded (eligibility rules, downed
state checks, a configurable ask-first gate) and labeled in-game as
*"Execute action: experimental — community feedback welcome."* It can be disabled
entirely in the MCM.

**The pose picker is retired.** Pose picking now happens in one pass: the Muse
consideration prompt reads the live pose catalog (per-category move lists with content
descriptions) and answers with both the pose and the exact move. The old separate
pose-picker decision step no longer exists — there is nothing to configure.

**OStim self-drive (FHU).** OStim scenes drive their own inflation fills via the built-in
climax driver; no SexLab bridge is required for OStim users.

## Credits

**Around906** — original author of the SkyrimNet Animations — GS Poser, SkyrimNet Baka
Integration, and SkyrimNet Acheron Integration sections this project builds on. DeD
started as a consolidation and re-release of that work: released with his permission
(private communication, archived), under his community-spirited full-takeover grant
(2026-10-07 / 2026-10-12) — credited here first and prominently, per the record. This
project would not exist without his mods and his generosity.

Delectatio et Dominium is a full re-release of the project under its own name: the
upcoming version is a different beast from when Around906 put the project down, with
restructured content packs, a new MCM, and new modules — but the lineage is his.

Other credits: the [Gunslicer](https://www.loverslab.com/) poses animation pack
(GS Poses), [Acheron](https://www.loverslab.com/),
[CommonLibSSE-NG / CommonLibVR](https://github.com/alandtse/CommonLibVR)
contributors, and the SkyrimNet project.

**Oldcustard** — community contributor: the creature-struggle fix batch from his PR #2
(six of seven fixes folded, plus the Execute mention phrasing on the downed cue), folded
with his consent.

## Disclaimer

> I realize some of the content in these modules is fairly extreme. While I can't and
> don't judge what roleplay my fellow gamers want to pursue in their sessions, I want to
> make clear that these theme explorations are only acceptable because they are happening
> in a harmless environment of code and animation. The game represents an environment
> where the users agree with themselves, as adults, to explore, roleplay, and visualize
> these themes, as if they were writing a story for themselves on the topic. The content
> of this roleplay is not meant to be shared or to produce content for anyone else, and
> the whole process is built to be consensual by definition. The existence of these
> modules and the themes they cover are in no way meant to encourage or normalize this
> kind of behavior in the real world. They exist in this mod because their moral
> repugnancy and cultural taboo shock, thrill, and horrify in the same way they would in
> a TV show, or movie. I will belabor the point no more, but I hope it is well made.
> Enjoy the mod for what it is, and do not take it as an endorsement for real sexual
> violence or illegal activaties.

*(Disclaimer text by the project's author, transcribed verbatim.)*

## Roadmap

This is **v0.3.0-alpha — the first full release.** Every module above is shipped,
polished, and dogfood-tested: the background-daemon era (the Baka Muse modes, the
consideration-prompt pose system), the Cum / FHU / SlaveTats v2 systems with their
ambient narration layers, the independence audit, and the full story-voice pass are all
in. Version numbers will increment as milestones ship — plans include further mod
integrations and deeper scene-aware reactions. The v0.1.0 polish-and-expansion pass this
README once promised is done.

## License

MIT — see [LICENSE](LICENSE).
