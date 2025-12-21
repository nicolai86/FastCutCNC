description = "SimCNC Plasma";
vendor = "CS-Lab";
vendorUrl = "https://en.cs-lab.eu/";
legal = "Copyright (C) 2025 Raphael Randschau";
certificationLevel = 2;
minimumRevision = 1;
longDescription = "Fusion 360 post for SimCNC plasma cutting. Supports basic torch control, heights, and optional G41/G42.";
extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.002, MM);
minimumChordLength = spatial(0.00001, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.00001);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = (1 << PLANE_XY);
circularMergeTolerance = spatial(0.002, MM);

properties = {
    writeMachine: {
        title: "Write machine",
        description: "Output the machine settings in the header of the code.",
        group: "formats",
        type: "boolean",
        value: false,
        scope: "post"
    },
    safeRetractHeight: {
        title: "Safe retract height",
        description: "The Z height to retract to between cuts (in machine units).",
        group: "home",
        type: "number",
        value: (unit == MM ? 25.4 : 1.0),
        scope: "post"
    },
    useM3M5: {
        title: "Use M3/M5 for torch",
        description: "Use M3/M5 for torch on/off. Disable to use M62/M63 for synchronized outputs.",
        group: "preferences",
        type: "boolean",
        value: true,
        scope: "post"
    },
    defaultFeedRateOverride: {
        title: "Default FRO",
        description: "Default FRO. 100 = off",
        group: "FROs",
        type: "number",
        value: 100.0,
        scope: "post"
    },
    rapidFeedRateOverride: {
        title: "Default FRO for rapids",
        description: "Default FRO for rapids.",
        group: "FROs",
        type: "number",
        value: 100.0,
        scope: "post"
    },
    useCutterComp: {
        title: "Use cutter compensation",
        description: "Enable G41/G42 for in-control kerf comp. Warning: SimCNC may not support; test thoroughly.",
        group: "preferences",
        type: "boolean",
        value: true,
        scope: "post"
    },
    compOffsetNumber: {
        title: "Compensation offset number",
        description: "D offset number for G41/G42 (0 to disable D output).",
        group: "preferences",
        type: "integer",
        value: 1,
        scope: "post"
    },
    showSequenceNumbers: {
        title: "Show sequence numbers",
        description: "Add N numbers to lines.",
        group: "formats",
        type: "boolean",
        value: false,
        scope: "post"
    },
    sequenceNumberStart: {
        title: "Start sequence number",
        description: "Starting N number.",
        group: "formats",
        type: "integer",
        value: 10,
        scope: "post"
    },
    sequenceNumberIncrement: {
        title: "Sequence increment",
        description: "N increment value.",
        group: "formats",
        type: "integer",
        value: 5,
        scope: "post"
    },
    separateWordsWithSpace: {
        title: "Separate words with space",
        description: "Adds spaces between words if 'yes' is selected.",
        type: "boolean",
        value: true,
        scope: "post"
    },
    froOverride: {
        title: "FRO override",
        description: "Feed rate override for profile (e.g., in slots). Set to 100 for no override.",
        group: "FROs",
        type: "number",
        value: 100.0,
        scope: "operation"  // Ensures it's per-operation
    },
    disableThc: {
        title: "Disable THC",
        description: "",
        group: "preferences",
        type: "boolean",
        value: false,
        scope: "operation"
    },
};
// formats
var gFormat = createFormat({
    prefix: "G",
    decimals: 0,
    width: 2,
    zeropad: true
});
var mFormat = createFormat({
    prefix: "M",
    decimals: 0,
    width: 2,
    zeropad: true
});
var xyzFormat = createFormat({
    decimals: (unit == MM ? 4 : 5),
    forceDecimal: true
});
var feedFormat = createFormat({
    decimals: (unit == MM ? 1 : 2),
    forceDecimal: true
});
var secFormat = createFormat({
    decimals: 3,
    forceDecimal: true
});
var xOutput = createVariable({
    prefix: "X"
}, xyzFormat);
var yOutput = createVariable({
    prefix: "Y"
}, xyzFormat);
var zOutput = createVariable({
    prefix: "Z"
}, xyzFormat);
var iOutput = createVariable({
    prefix: "I"
}, xyzFormat);
var jOutput = createVariable({
    prefix: "J"
}, xyzFormat);
var dOutput = createVariable({
    prefix: "D"
}, xyzFormat);
var feedOutput = createVariable({
    prefix: "F"
}, feedFormat);
var rOutput = createFormat({
    prefix: "R",
    decimals: (unit == MM ? 4 : 5),
    forceDecimal: true
}); // For R radius
// modals
var isFirstMotion = true;
var gMotionModal = createModal({}, gFormat); // G0  - G3
var gAbsIncModal = createModal({}, gFormat); // G90 - G91
var gUnitModal = createModal({}, gFormat);   // G20 - G21
var gCompensationModal = createModal({}, gFormat); // G40-G42
var gWorkModal = createModal({}, gFormat); // G54 - ...
var gPlaneModal = createModal({}, gFormat);
var sequenceNumber = getProperty('sequenceNumberStart');
var pendingRadiusCompensation = -1;
var firstRapidAfterSection = false;


function getFramePosition(pos) {
    return pos;
}

function getCurrentPositionSafe() {
    var pos = getCurrentPosition();
    var safePos = new Vector(
        isNaN(pos.x) ? 0 : pos.x,
        isNaN(pos.y) ? 0 : pos.y,
        isNaN(pos.z) ? getProperty('safeRetractHeight') : pos.z
    );
    return safePos;
}

function formatWords() {
    if (arguments.length == 0) {
        return "";
    }
    var result = "";
    for (var i = 0; i < arguments.length; ++i) {
        if (arguments[i]) {
            if (result) {
                result += getProperty('separateWordsWithSpace') ? " " : "";
            }
            result += arguments[i];
        }
    }
    return result;
}

function formatWords2(prefix) {
    if (arguments.length == 1) {
        return prefix;
    }
    var result = prefix;
    for (var i = 1; i < arguments.length; ++i) {
        if (arguments[i]) {
            result += getProperty('separateWordsWithSpace') ? " " : "";
            result += arguments[i];
        }
    }
    return result;
}

function writeWords() {
    var line = formatWords.apply(null, arguments);
    if (line) {
        writeln(line);
    }
}

function writeWords2(prefix) {
    var line = formatWords2.apply(null, arguments);
    if (line) {
        writeln(line);
    }
}

function writeBlock() {
    if (properties.showSequenceNumbers.value) {
        if (arguments.length > 0) {
            var words = [];
            for (var i = 0; i < arguments.length; ++i) {
                words.push(arguments[i]);
            }
            writeWords2("N" + sequenceNumber, words);
            sequenceNumber += properties.sequenceNumberIncrement.value;
        }
    } else {
        writeWords.apply(null, arguments);
    }
}

function writeComment(text) {
    writeln("(" + text + ")");
}

function onOpen() {
    // absolute coordinates
    writeBlock(gAbsIncModal.format(90));
    // units
    switch (unit) {
        case IN:
            writeBlock(gUnitModal.format(20));
            break;
        case MM:
            writeBlock(gUnitModal.format(21));
            break;
    }
    // plane select
    writeBlock(gFormat.format(17));
    // comp off
    writeBlock(gCompensationModal.format(40));
}

function onComment(message) {
    writeComment(message);
}

function forceXYZ() {
    xOutput.reset();
    yOutput.reset();
    zOutput.reset();
}

function forceAny() {
    forceXYZ();
    feedOutput.reset();
}

var lastM220 = undefined;
function writeM220(value) {
    if (lastM220 === value) {
        return;
    }
    writeBlock(
        `#1000=${value}`,
        mFormat.format(220)
    );
    lastM220 = value;
}

function onSection() {
    firstRapidAfterSection = true;

    if (hasParameter("operation-comment")) {
        var comment = getParameter("operation-comment");
        if (comment) {
            writeComment(comment);
        }
    }
    // rapid to initial position
    if (!isFast) {
        writeM220(getProperty('rapidFeedRateOverride'));
        isFast = true;
    }
    forceAny();
    var initialPosition = getFramePosition(currentSection.getInitialPosition());
    var initialX = 0;
    var initialY = 0;
    var initialZ = getProperty('safeRetractHeight');
    if (initialPosition) {
        initialX = isNaN(initialPosition.x) ? 0 : initialPosition.x;
        initialY = isNaN(initialPosition.y) ? 0 : initialPosition.y;
    }
    gMotionModal.reset();
    writeBlock(gMotionModal.format(0),
        xOutput.format(initialX),
        yOutput.format(initialY),
        zOutput.format(initialZ));
}

function onParameter(name, value) {
    // TODO: are any of these useful?
}

function onPower(power) {
    slowDown();

    var froValue = currentSection.properties.froOverride;
    var applyFRO = (froValue !== undefined && froValue != 100);
    if (power) {
        redirectToBuffer();

        if (currentSection.properties.disableThc) {
            writeBlock(
                // disable THC by blocking anti dive
                '#50 = #4061',
                '#4061 = 100'
            );
        }


        if (applyFRO) {
            writeM220(froValue);
        }

        if (getProperty('useM3M5')) {
            writeBlock(mFormat.format(3));
        } else {
            writeBlock(mFormat.format(62), "P0");
        }
    } else {
        var fullOutput = getRedirectionBuffer();
        closeRedirection();


        write(fullOutput);

        if (currentSection.properties.disableThc) {
            // restore THC
            writeBlock(
                '#4061 = #50',
            );
        }

        if (getProperty('useM3M5')) {
            writeBlock(mFormat.format(5));
        } else {
            writeBlock(mFormat.format(63), "P0");
        }

        if (applyFRO) {
            writeM220(getProperty('defaultFeedRateOverride'));
        }
    }
}

function onDwell(seconds) {
    writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}

function onRadiusCompensation() {
    pendingRadiusCompensation = radiusCompensation;
    if (pendingRadiusCompensation >= 0) {
        if (!getProperty('useCutterComp') && radiusCompensation != RADIUS_COMPENSATION_OFF) {
            warning("Cutter compensation requested but disabled in post properties. Outputting uncompensated path.");
            pendingRadiusCompensation = -1;
            return;
        }
    }
}

var isFast = false;
function onRapid(_x, _y, _z) {
    if (firstRapidAfterSection) {
        firstRapidAfterSection = false;
        return;
    }
    var x = xOutput.format(_x);
    var y = yOutput.format(_y);
    var z = zOutput.format(_z);
    if (x || y || z) {
        if (pendingRadiusCompensation >= 0) {
            onRadiusCompensation();
        }
        gMotionModal.reset();
        if (!isFast) {
            writeM220(getProperty('rapidFeedRateOverride'));
            isFast = true;
        }
        writeBlock(
            gMotionModal.format(0), x, y, z);

    }
}

function slowDown() {
    if (!isFast) {
        return;
    }

    writeM220(getProperty('defaultFeedRateOverride'));
    isFast = false;
}

function onLinear(x, y, z, feed) {
    slowDown();
    var _x = xOutput.format(x);
    var _y = yOutput.format(y);
    var _z = zOutput.format(z);

    if (pendingRadiusCompensation >= 0) {
        pendingRadiusCompensation = -1;
        var d = tool.diameterOffset;
        // For plasma, set tool diameter in SimCNC. Correction happens via G41/ G42
        switch (radiusCompensation) {
            case RADIUS_COMPENSATION_LEFT:
                dOutput.reset();
                writeBlock(
                    gPlaneModal.format(17),
                    gMotionModal.format(1),
                    gCompensationModal.format(41),
                    _x,
                    _y,
                    _z,
                    dOutput.format(d));
                break;
            case RADIUS_COMPENSATION_RIGHT:
                dOutput.reset();
                writeBlock(
                    gPlaneModal.format(17),
                    gMotionModal.format(1),
                    gCompensationModal.format(42),
                    _x,
                    _y,
                    _z,
                    dOutput.format(d));
                break;
            case RADIUS_COMPENSATION_OFF:
                writeBlock(
                    gPlaneModal.format(17),
                    gMotionModal.format(1),
                    gCompensationModal.format(40),
                    _x,
                    _y,
                    _z);
                break;
            default:
                error(localize("Unsupported radius compensation."));
        }
    } else {
        writeBlock(
            gMotionModal.format(1),
            _x,
            _y,
            _z
        );
    }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
    slowDown();
    var start = getCurrentPosition();

    if (isFullCircle()) {
        if (getCircularPlane() != PLANE_XY) {
            linearize(tolerance);
            return;
        }

        // For full circle in XY, output two semicircles or linearize if unsupported
        // Safe minimal approach for plasma
        linearize(tolerance);
        return;
    }

    if (getCircularPlane() == PLANE_XY) {
        writeBlock(
            gPlaneModal.format(17),
            gMotionModal.format(clockwise ? 2 : 3),
            xOutput.format(x),
            yOutput.format(y),
            zOutput.format(z),
            iOutput.format(cx - start.x),
            jOutput.format(cy - start.y),
        );
    } else {
        linearize(tolerance);
    }
}

function onSectionEnd() {
    if (getProperty('useCutterComp')) {
        writeBlock(gCompensationModal.format(40));
    }
    gMotionModal.reset();
    writeM220(getProperty('defaultFeedRateOverride'));
}

function onClose() {
    // disable compensation
    writeBlock(gCompensationModal.format(40));
    // return home
    writeBlock(
        gAbsIncModal.format(90),
        gWorkModal.format(55));
    gMotionModal.reset();
    writeBlock(
        gMotionModal.format(0),
        zOutput.format(getProperty('safeRetractHeight'))
    );
    writeBlock(
        gMotionModal.format(0),
        xOutput.format(0), yOutput.format(0)
    );
    // rewind
    writeBlock(mFormat.format(30));
}