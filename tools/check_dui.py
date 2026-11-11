#!/usr/bin/env python3
"""Checks that every name of Dialogue UI that EasyGear/DialogueUI.lua uses exists in Dialogue UI's own source.

    check_dui.py <folder of the Dialogue UI addon>     (the one with DialogueUI.toc; e.g. a clone of
                                                        https://github.com/Peterodox/YUI-Dialogue)

EasyGear touches Dialogue UI only through these names (see the header of DialogueUI.lua). Dialogue UI is a different
addon and changes on its own: run this after each new version of it. Exit code 1 if a name is missing.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = sys.argv[1] if len(sys.argv) > 1 else None
if not SRC or not os.path.isfile(os.path.join(SRC, "DialogueUI.toc")):
    sys.exit("usage: check_dui.py <folder of the Dialogue UI addon (with DialogueUI.toc)>")

# name -> what must be found in Dialogue UI's Lua / XML files (regular expressions, any file)
NEEDED = {
    # public interface (Code/Tooltip/Tooltip_Public.lua, Initialization.lua)
    "DialogueUIAPI.AddItemTooltipProcessorExternal": r"DialogueUIAPI\.AddItemTooltipProcessorExternal\s*=",
    "DialogueUI_DB (saved variable)": r"##\s*SavedVariables:.*DialogueUI_DB",
    "DialogueUI_DB.TooltipShowItemComparison": r"TooltipShowItemComparison",
    # the tooltip (Tooltip_Base.lua, Tooltip_Private.lua)
    "tooltip:AddLeftLine": r"function\s+\w+:AddLeftLine\(",
    "tooltip:AddRightLine": r"function\s+\w+:AddRightLine\(",
    "tooltip:AddBlankLine": r"function\s+\w+:AddBlankLine\(",
    "tooltip:ReprocessInfo": r"function\s+\w+:ReprocessInfo\(",
    "tooltip:ReTriggerOnEnter": r"function\s+\w+:ReTriggerOnEnter\(",
    "tooltip:GetHyperlink": r"function\s+\w+:GetHyperlink\(",
    "button:OnEnter": r"function\s+ItemButtonSharedMixin:OnEnter\(",
    "tooltip:ProcessItemExternal": r"function\s+\w+:ProcessItemExternal\(",
    "tooltip.owner (SetOwner)": r"self\.owner\s*=\s*owner",
    "SharedTooltip.SetItem callback": r"\"SharedTooltip\.SetItem\"",
    # the quest frame and its reward buttons (DialogueUI.xml, DialogueUI.lua, UITemplates.lua)
    "DUIQuestFrame": r"<Frame\s+name=\"DUIQuestFrame\"",
    "DUIQuestFrame:IsChoosingReward": r"function\s+\w+:IsChoosingReward\(",
    "DUIQuestFrame:ReleaseAllObjects": r"function\s+DUIDialogBaseMixin:ReleaseAllObjects\(",
    "DUIQuestFrame.itemButtonPool": r"self\.itemButtonPool\s*=",
    "pool:ProcessActiveObjects": r"function\s+ObjectPoolMixin:ProcessActiveObjects\(",
    "button:DoesButtonHaveMarker": r"function\s+ItemButtonSharedMixin:DoesButtonHaveMarker\(",
    "button:ShowUpgradeIcon": r"function\s+ItemButtonSharedMixin:ShowUpgradeIcon\(",
    "button.Icon": r"self\.Icon:SetTexture\(texture\)",
    "button.type / button.index / button.objectType": r"self\.objectType\s*=\s*\"item\"",
}

text = []
for dirpath, _, names in os.walk(SRC):
    for n in names:
        if n.endswith((".lua", ".xml", ".toc")):
            with open(os.path.join(dirpath, n), encoding="utf-8", errors="replace") as f:
                text.append(f.read())
blob = "\n".join(text)

bad = [name for name, pat in NEEDED.items() if not re.search(pat, blob)]
version = re.search(r"^## Version:\s*(.+)$", open(os.path.join(SRC, "DialogueUI.toc"), encoding="utf-8").read(), re.M)
print("Dialogue UI %s" % (version.group(1).strip() if version else "?"))
for name in bad:
    print("MISSING  " + name)
if bad:
    print("%d of %d names are missing" % (len(bad), len(NEEDED)))
    sys.exit(1)
print("Dialogue UI check: all %d names EasyGear uses exist" % len(NEEDED))
