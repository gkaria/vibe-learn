# Renders docs/demo/social-preview.png (1280x640) for the GitHub social preview.
# Run from the repo root: vhs docs/demo/social-preview.tape
Output docs/demo/social-preview-frames.gif

Set Shell bash
Set FontSize 20
Set Width 1280
Set Height 640
Set Padding 30
Set Theme "Catppuccin Mocha"
Set Framerate 5

Hide
Type "clear && bash docs/demo/social-preview.sh"
Enter
Sleep 1s
Show
Sleep 500ms
Screenshot docs/demo/social-preview.png
Sleep 200ms
