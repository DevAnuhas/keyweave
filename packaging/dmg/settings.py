"""Finder layout for the KeyWeave installer."""
from pathlib import Path

app = Path(defines["app"])
resources = Path(defines["resources"])
files = [(str(app), "KeyWeave.app"), (defines["license"], "License.txt")]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
filesystem = "HFS+"
icon = str(app / "Contents/Resources/AppIcon.icns")
background = str(resources / "background.png")
# The 400-point artwork leaves room for Finder's optional path/status bars.
window_rect = ((180, 180), (600, 500))
default_view = "icon-view"
show_status_bar = show_tab_view = show_toolbar = show_pathbar = show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 80
scroll_position = (0, 0)
icon_size = 80
text_size = 13
label_pos = "bottom"
icon_locations = {
    "KeyWeave.app": (150, 180),
    "Applications": (450, 180),
    "License.txt": (520, 320),
}
# Never set FinderInfo flags on the signed app; codesign --strict rejects them.
