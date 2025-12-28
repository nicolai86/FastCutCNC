import re
import math


def calculate_frame_and_outline(gcode):
    """
    Given arbitrary G-code, calculates the minimum bounding rectangle (frame) that contains all shapes,
    and generates G-code to perform a rectangular move outlining this frame.
    Handles G0, G1, G2, G3, G90, G91. Assumes IJ for arcs (not R).
    """
    lines = gcode.splitlines()
    current_x = 0.0
    current_y = 0.0
    min_x = float("inf")
    max_x = float("-inf")
    min_y = float("inf")
    max_y = float("-inf")
    move_mode = 0  # 0: G0, 1: G1, 2: G2, 3: G3
    pos_mode = 90  # 90: absolute, 91: relative
    units = None

    for line in lines:
        line = line.upper().split(";")[0].strip()  # Remove comments
        if not line:
            continue
        words = re.findall(r"([A-Z])(-?\d*\.?\d+)", line)
        target_x = None
        target_y = None
        i = None
        j = None
        for letter, value in words:
            val = float(value)
            if letter == "G":
                gval = int(val)
                if gval in [0, 1, 2, 3]:
                    move_mode = gval
                elif gval == 90:
                    pos_mode = 90
                elif gval == 91:
                    pos_mode = 91
                elif gval == 20:
                    units = 20
                elif gval == 21:
                    units = 21
            elif letter == "X":
                target_x = val
            elif letter == "Y":
                target_y = val
            elif letter == "I":
                i = val
            elif letter == "J":
                j = val
            # Ignore other parameters like Z, F, etc.

        # If no X or Y, no movement
        if target_x is None and target_y is None:
            continue

        # Compute absolute target positions
        tx = (
            (current_x + target_x if target_x is not None else current_x)
            if pos_mode == 91
            else (target_x if target_x is not None else current_x)
        )
        ty = (
            (current_y + target_y if target_y is not None else current_y)
            if pos_mode == 91
            else (target_y if target_y is not None else current_y)
        )

        if move_mode in [0, 1]:  # Linear or rapid move
            # Update bounding box with start and end points
            min_x = min(min_x, current_x, tx)
            max_x = max(max_x, current_x, tx)
            min_y = min(min_y, current_y, ty)
            max_y = max(max_y, current_y, ty)
        elif move_mode in [2, 3]:  # Arc move
            if i is None or j is None:
                continue  # Skip if no IJ (R not supported)
            # I J are always incremental from current position, regardless of G90/G91
            cx = current_x + i
            cy = current_y + j
            is_cw = move_mode == 2

            # Update with start and end points
            min_x = min(min_x, current_x, tx)
            max_x = max(max_x, current_x, tx)
            min_y = min(min_y, current_y, ty)
            max_y = max(max_y, current_y, ty)

            # Calculate radius
            r = math.sqrt((current_x - cx) ** 2 + (current_y - cy) ** 2)

            # Extreme points and their angles (0 to 2pi)
            extremes = [
                (cx + r, cy, 0.0),  # right (east)
                (cx, cy + r, math.pi / 2),  # up (north)
                (cx - r, cy, math.pi),  # left (west)
                (cx, cy - r, 3 * math.pi / 2),  # down (south)
            ]

            start_angle = math.atan2(current_y - cy, current_x - cx) % (2 * math.pi)
            end_angle = math.atan2(ty - cy, tx - cx) % (2 * math.pi)

            if not is_cw:  # CCW
                if end_angle < start_angle:
                    end_angle += 2 * math.pi
                for ex, ey, eangle in extremes:
                    if start_angle <= eangle <= end_angle:
                        min_x = min(min_x, ex)
                        max_x = max(max_x, ex)
                        min_y = min(min_y, ey)
                        max_y = max(max_y, ey)
            else:  # CW
                if start_angle < end_angle:
                    start_angle += 2 * math.pi
                for ex, ey, eangle in extremes:
                    if end_angle <= eangle <= start_angle:
                        min_x = min(min_x, ex)
                        max_x = max(max_x, ex)
                        min_y = min(min_y, ey)
                        max_y = max(max_y, ey)

        # Update current position
        current_x = tx
        current_y = ty

    # If no movements, default to 0
    if min_x == float("inf"):
        min_x = max_x = min_y = max_y = 0.0

    units_command = "G21\n" if units == 21 else "G20\n" if units == 20 else ""
    # Generate outline G-code (move Z to homing height, rapid to start, then linear moves)
    outline_gcode = (
        units_command + "G90 (units from loaded gcode)\n"
        f"G0 X{min_x:.3f} Y{min_y:.3f}\n"
        f"G1 X{max_x:.3f} Y{min_y:.3f}\n"
        f"G1 X{max_x:.3f} Y{max_y:.3f}\n"
        f"G1 X{min_x:.3f} Y{max_y:.3f}\n"
        f"G1 X{min_x:.3f} Y{min_y:.3f}\n"
    )
    return outline_gcode, units


# SimCNC script to read loaded G-code and execute outline
try:
    # Get current position in program coordinates (G54)
    pos = d.getPosition(CoordMode.Program)

    feedrate = gui.edFeedrate.getText().strip()
    original_feedrate = feedrate
    if not feedrate:
        feedrate = float("2000")
    else:
        feedrate = float(feedrate)

    # Get the file path from the UI label (assuming default widget name 'lbFileName' displays the full path)
    file_path = gui.lbGCodeName.getText()

    if not file_path:
        print("No G-code file loaded or widget not found.")
    else:
        with open(file_path, "r") as f:
            gcode = f.read()

        outline, units = calculate_frame_and_outline(gcode)
        if units == 21:  # mm
            feedrate = feedrate * 25.4
        outline = outline.replace("G1 ", f"G1 F{feedrate:.1f} ")
        # Add postamble to move back to original XY position and M30
        outline += (
            f"G0 X{pos[0]:.3f} Y{pos[1]:.3f}\n#1000={original_feedrate} M221\nM30\n"
        )
        print(outline)
        # Execute the outline G-code in SimCNC
        d.executeGCodeList(outline.splitlines())

except AttributeError:
    print(
        "GUI widget 'lbFileName' not found. Ensure the screen has a label with that name connected to 'GCode file path' signal."
    )
except Exception as e:
    print(f"Error: {e}")
