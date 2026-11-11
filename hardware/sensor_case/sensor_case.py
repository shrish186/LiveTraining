"""Prototype leg-sensor case: Seeed XIAO nRF52840 Sense + 502030 LiPo, strapped to the shin or ankle.

Parametric (CadQuery). Change the numbers below and run:

    pip install cadquery
    python sensor_case.py            # writes case_body / case_lid as .step and .stl

Layout (sensor long axis along the shin):
  - Battery on the floor, XIAO on top of it, pushed against the +X wall where its USB-C port is.
  - Strap loops on both long sides for a 25 mm elastic / hook-and-loop strap around the leg.
  - The underside is curved to sit on a leg (radius LEG_RADIUS) so the case can't rock: a rigid
    mount matters more for clean impact peaks than anything else here.
  - An arrow on the lid points toward the foot, so every session is worn the same way round.
Print in PETG or TPU-reinforced PETG, 0.2 mm layers, 30% infill. Lid is a friction fit (+ a dab of glue
or tape once tested).
"""

from pathlib import Path

import cadquery as cq

# --- parts -------------------------------------------------------------------------------------
XIAO_L, XIAO_W, XIAO_H = 21.0, 17.8, 3.6      # board incl. components (mm)
BATT_L, BATT_W, BATT_H = 30.0, 20.0, 5.0      # 502030 LiPo, ~250 mAh
USB_W, USB_H = 9.4, 3.6                       # USB-C receptacle opening
STACK_GAP = 0.6                               # foam tape between battery and board

# --- case --------------------------------------------------------------------------------------
CLEAR = 1.0          # clearance around the parts
WALL = 1.8
FLOOR = 1.8
LID = 1.6
LID_LIP = 1.6        # depth of the lid lip that plugs into the case
FIT = 0.2            # lid lip clearance per side
CORNER_R = 3.0
STRAP_W = 25.0       # strap width
STRAP_T = 3.0        # slot height (strap thickness + play)
TAB = 7.5            # strap loop reach beyond the wall
SLOT_GAP = 1.5       # wall to strap slot
LEG_RADIUS = 45.0    # underside curvature (shin/ankle)
LED_HOLE_D = 2.0

IN_L = max(XIAO_L, BATT_L) + 2 * CLEAR
IN_W = max(XIAO_W, BATT_W) + 2 * CLEAR
IN_H = BATT_H + STACK_GAP + XIAO_H + LID_LIP + 0.6   # the lid lip must clear the USB-C connector
OUT_L, OUT_W = IN_L + 2 * WALL, IN_W + 2 * WALL
OUT_H = FLOOR + IN_H
SAG = LEG_RADIUS - (LEG_RADIUS ** 2 - ((OUT_W + 2 * TAB) / 2) ** 2) ** 0.5  # curve depth at the tab tips


def body() -> cq.Workplane:
    shell = (
        cq.Workplane("XY")
        .box(OUT_L, OUT_W, OUT_H + SAG, centered=(True, True, False))
        .translate((0, 0, -SAG))
        .edges("|Z").fillet(CORNER_R)
    )
    cavity = (
        cq.Workplane("XY", origin=(0, 0, FLOOR))
        .box(IN_L, IN_W, IN_H + 1, centered=(True, True, False))
        .edges("|Z").fillet(max(CORNER_R - WALL, 0.5))
    )
    shell = shell.cut(cavity)

    # Strap loops on both long sides, flush with the curved bottom.
    tab_h = STRAP_T + 2 * 1.6
    for side in (1, -1):
        y = side * (OUT_W / 2 + TAB / 2 - 0.5)
        tab = (
            cq.Workplane("XY")
            .box(STRAP_W + 6, TAB + 1, tab_h + SAG, centered=(True, True, False))
            .translate((0, y, -SAG))
            .edges("|Z").fillet(1.5)
        )
        slot = cq.Workplane("XY").box(STRAP_W + 1, STRAP_T, tab_h + SAG + 2).translate(
            (0, side * (OUT_W / 2 + SLOT_GAP + STRAP_T / 2), (tab_h - SAG) / 2)
        )
        shell = shell.union(tab).cut(slot)

    # Curved underside: a cylinder along X (the shin) takes out the middle.
    leg = cq.Workplane("YZ").circle(LEG_RADIUS).extrude(OUT_L + 20).translate(
        (-(OUT_L + 20) / 2, 0, -SAG - LEG_RADIUS + SAG)
    )
    shell = shell.cut(leg)

    # USB-C opening in the +X wall, centred on the board's connector height.
    usb_z = FLOOR + BATT_H + STACK_GAP + 1.2 + USB_H / 2 - 0.4
    usb = (
        cq.Workplane("YZ", origin=(OUT_L / 2 - WALL - 0.5, 0, usb_z))
        .rect(USB_W, USB_H)
        .extrude(WALL + 1)
        .edges("|X").fillet(1.2)
    )
    return shell.cut(usb)


def lid() -> cq.Workplane:
    plate = (
        cq.Workplane("XY")
        .box(OUT_L, OUT_W, LID, centered=(True, True, False))
        .edges("|Z").fillet(CORNER_R)
    )
    lip = (
        cq.Workplane("XY", origin=(0, 0, -LID_LIP))
        .box(IN_L - 2 * FIT, IN_W - 2 * FIT, LID_LIP, centered=(True, True, False))
        .edges("|Z").fillet(max(CORNER_R - WALL - FIT, 0.5))
    )
    hollow = cq.Workplane("XY", origin=(0, 0, -LID_LIP - 0.1)).box(
        IN_L - 2 * FIT - 2.4, IN_W - 2 * FIT - 2.4, LID_LIP + 0.1, centered=(True, True, False)
    )
    part = plate.union(lip).cut(hollow)
    # LED window above the XIAO's LED (near the USB end).
    part = part.cut(
        cq.Workplane("XY", origin=(OUT_L / 2 - WALL - 5.5, 3.0, -LID_LIP - 1)).circle(LED_HOLE_D / 2).extrude(LID + LID_LIP + 2)
    )
    # Arrow toward the foot (-X when the USB end points up the leg), engraved 0.6 mm.
    arrow = (
        cq.Workplane("XY", origin=(0, 0, LID - 0.6))
        .polyline([(-11, 0), (-4, -5), (-4, -2), (8, -2), (8, 2), (-4, 2), (-4, 5)])
        .close()
        .extrude(1)
    )
    return part.cut(arrow)


def main() -> None:
    out = Path(__file__).resolve().parent
    b, lid_part = body(), lid()
    for name, part in (("case_body", b), ("case_lid", lid_part)):
        cq.exporters.export(part, str(out / f"{name}.step"))
        cq.exporters.export(part, str(out / f"{name}.stl"), tolerance=0.05, angularTolerance=0.1)
    bb = b.val().BoundingBox()
    print(f"case outside: {bb.xlen:.1f} x {bb.ylen:.1f} x {bb.zlen:.1f} mm (incl. strap loops)")
    print(f"cavity: {IN_L:.1f} x {IN_W:.1f} x {IN_H:.1f} mm, lid {LID} mm + {LID_LIP} mm lip")


if __name__ == "__main__":
    main()
