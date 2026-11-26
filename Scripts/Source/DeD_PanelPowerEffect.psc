Scriptname DeD_PanelPowerEffect extends ActiveMagicEffect
{ The DeD lesser power (Magelight Phase 2 leg 6): opens the combined DeD panel. DeDService routes the
  press to a module (Baka claims it and runs its own checks; otherwise the last place or the default). }

Event OnEffectStart(Actor akTarget, Actor akCaster)
    Debug.Trace("[DeDService][PANEL] DeD power cast")
    If !DeDService.OpenPanel(akCaster)
        Debug.Trace("[DeDService][PANEL] DeD power: no panel (Magelight UI or the panel page is missing)")
    EndIf
EndEvent
