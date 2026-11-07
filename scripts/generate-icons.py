"""Regenerate the original vector-style sprout app icon (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent / "Resources"
image = Image.new("RGBA", (1024, 1024))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((32, 32, 992, 992), radius=208, fill="#F6F4EA")
draw.ellipse((235, 823, 795, 890), fill="#DBE3D1")
draw.line((512, 720, 512, 290), fill="#4D7955", width=35)
draw.ellipse((257, 300, 510, 485), fill="#91BA7E")
draw.ellipse((510, 213, 779, 418), fill="#619666")
draw.line((512, 450, 345, 366), fill="#719F66", width=14)
draw.line((512, 359, 684, 282), fill="#497D51", width=14)
draw.polygon(((282, 641), (742, 641), (684, 839), (340, 839)), fill="#BECFA8")
draw.rounded_rectangle((258, 610, 766, 688), radius=29, fill="#D2DFBB")
draw.ellipse((402, 724, 428, 754), fill="#42513D")
draw.ellipse((596, 724, 622, 754), fill="#42513D")
draw.arc((470, 749, 554, 803), 0, 180, fill="#42513D", width=12)
image.save(root / "AppIcon.png")
image.save(root / "AppIcon.ico", sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
image.save(root / "AppIcon.icns")
