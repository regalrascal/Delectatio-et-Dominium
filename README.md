# Delectatio et Dominium

<p align="center">
  <img src="Delectatio_et_Dominium_Cover.jpg" alt="Delectatio et Dominium" width="480">
</p>

**Bedroom drama for SkyrimNet.**

Delectatio et Dominium (DeD) is a **modular SkyrimNet integration framework** for adult
Skyrim modding. Instead of one monolithic adult mod, DeD is a set of modules that hook
auxiliary and niche adult mods into [SkyrimNet](https://github.com/goncalo22/SkyrimNet) —
so the LLM driving your NPCs can perceive and act on what those mods are actually doing
to (and around) the player and other characters. The structural idea: a modular framework
that can support a number of mods while requiring as few as one of them. Each module is a
separable file-set with a FOMOD installer option, so you install only what you use.

> ⚠️ **Adult content (18+).** This mod adds non-consensual / NSFW interactions and other
> extreme roleplay themes. See the disclaimer below before installing.

---

## Modules

| Module | What it does |
| --- | --- |
| **Baka Interactions** | Paired NSFW interactions through the Interact power — affectionate, forced, and sexual actions targeted at any NPC, a downed victim, a hostile creature, or yourself — plus an escalation system (resist / struggle / submit / call for help), capture, tie-up, slavery, creature escalation, and a full MCM. |
| **GS Poses** | Solo posing: a PrismaUI pose-grid selector (19 high-quality pose categories on the player or any targeted NPC) and LLM-driven contextual NPC posing — the **Muse** background daemon that puts nearby NPCs into mood-fitting poses, grounded by an LLM consideration prompt. Shares one flat pose category with Baka Interactions. |
| **Cum** | SkyrimNet triggers when cum is applied (the OCum ModEvent path, plus a SexLab end-of-scene proxy), with unified and per-source firing modes. |
| **FHU** | [Fill Her Up — Baka Edition](https://www.loverslab.com/) inflation level cues, keyed to its inflation ModEvents. |
| **SlaveTats** | LLM-driven application of SlaveTats tattoo sets (spank marks, tears, drool, and related sets) with NPC/player reactions and an in-game tattoo menu. |
| **Acheron Bridge** | Downed-consequence SkyrimNet triggers bridged to [Acheron](https://www.loverslab.com/)'s consequence system. |

Nothing fires at random: every interaction and pose is decided by SkyrimNet's model, in
context, from the characters' personalities — expect emergent, unscripted moments rather
than canned scenes. Master toggles, an intensity slider, and per-module settings let you
dial everything back.

## Requirements

- [Skyrim Special Edition](https://store.steampowered.com/app/489830/The_Elder_Scrolls_V_Skyrim_Special_Edition/) 1.5.97+
- [SKSE64](https://skse.silverlock.org/) matching your runtime
- [SkyrimNet](https://goncalo22.github.io/SkyrimNet-GamePlugin/) (the LLM framework this mod integrates with — required)
- **SexLab Framework or OSex/OStim** — at least one adult animation framework (both are supported simultaneously)
- **Soft (strongly recommended):** an arousal framework — pick **ONE** of OSL Aroused
  Reborn or SL Aroused NG. Arousal-aware reactions key on it; if both are present the
  runtime resolves OSL Aroused Reborn first, then SL Aroused, else runs neutral.
- The module's target mod (OCum / Fill Her Up Baka Edition / SlaveTats / Acheron / the
  GSPoses animation pack by Gunslicer for GS Poses) — only for the modules you install.

## Installation

Install with a mod manager (Mod Organizer 2 recommended): the FOMOD wizard walks you
through the modules and installs only the file-sets you pick.

1. Install and configure the requirements above (SkyrimNet first).
2. Install DeD with MO2 — choose your modules in the wizard.
3. Launch via SKSE. Each installed module gets a configuration section in the
   **Delectatio et Dominium** MCM (Baka Interactions page + per-module sections).
4. In SkyrimNet's dashboard, verify the `regalrascal.*` content packs are listed.

Manual install: copy the folders from the archive into your `Data` directory and enable
the ESPs for your chosen modules — but the wizard is the supported path.


**EXPERIMENTAL — the Execute action.** The execute-on-downed-victim lane (Baka
Interactions) ships **experimental**: it is heavily guarded (eligibility rules, downed
state checks, a configurable ask-first gate) and labeled in-game as
*"Execute action: experimental — community feedback welcome."* It can be disabled
entirely in the MCM.

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

This is **v0.1.0 — the initial public version of a mod in active development.** Every
module above is pending its polish-and-expansion pass; version numbers will increment
as milestones ship. Plans include location-variant and bystander cum reactions with
arousal tiering, deeper Fill Her Up integration, dirty-talk improvements, and further
mod integrations.

## License

MIT — see [LICENSE](LICENSE).
