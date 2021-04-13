/**
  Copyright (C) 2012-2018 by Autodesk, Inc.
  All rights reserved.

  Gerber post processor configuration.

  $Revision: 41940 5749451b87db6fed3e48c2516a5fdf6bbc50a2e0 $
  $Date: 2018-04-18 15:11:35 $
  
  FORKID {A5EBE12B-E941-4F8C-B1D8-DF15B22F1368}
*/

description = "Gerber Conversational";
vendor = "Gerber";
vendorUrl = "http://www.gspinc.com";
legal = "Copyright (C) 2012-2018 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic milling post for Gerber conversational format. Only lead-in/out, plunge, and cutting feedrates will be used by this post processor.";

extension = "ger";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = (1 << PLANE_XY); // allow XY plane only

// user-defined properties
properties = {
};

// user-defined property definitions
propertyDefinitions = {
};

var xyzFormat = createFormat({decimals:(unit == MM ? 4 : 5), trim: false});
var zFormat = createFormat({decimals:(unit == MM ? 4 : 5),  trim: false, scale: -1});
var toolFormat = createFormat({decimals:0});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var rpmFormat = createFormat({decimals:0});
var mFormat = createFormat({decimals:0});

var xOutput = createVariable({force: true}, xyzFormat);
var yOutput = createVariable({force: true}, xyzFormat);
var zOutput = createVariable({force: true}, zFormat);
var feedOutput = createVariable({}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, rpmFormat);

/**
  Writes the specified block.
*/
function writeBlock() {
  var text = formatWords(arguments);
  if (text) {
    writeWords("#" + text );
  }
}

function formatComment(text) {
  return String(text).replace(/[\(\)]/g, "");
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeBlock("/ " + formatComment(text));
}

function onOpen() {

  setWordSeparator(" ");
/*
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }
  switch (unit) {
  case IN:
    writeBlock(gFormat.format(20));
    break;
  case MM:
    writeBlock(gFormat.format(21));
    break;
  }
*/
  writeBlock("R4000");
  writeBlock("R4100");
  writeBlock("R49000061A8");
  writeBlock("MJob Start. Load Matl");

  var workpiece = getWorkpiece();
  writeBlock(
    "L" + xyzFormat.format(workpiece.lower.x),
    xyzFormat.format(workpiece.lower.y),
    xyzFormat.format(workpiece.lower.z),
    xyzFormat.format(workpiece.upper.x),
    xyzFormat.format(workpiece.upper.y),
    xyzFormat.format(workpiece.upper.z)
  );
  writeBlock("R4101");
  writeBlock("R4001");
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X and Y. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X and Y. */
function forceAny() {
  forceXYZ();
}

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  var newWorkPlane = isFirstSection() ||
    !isSameDirection(getPreviousSection().getGlobalFinalToolAxis(), currentSection.getGlobalInitialToolAxis()) ||
    (currentSection.isOptimizedForMachine() && getPreviousSection().isOptimizedForMachine() &&
    Vector.diff(getPreviousSection().getFinalToolAxisABC(), currentSection.getInitialToolAxisABC()).length > 1e-4) ||
    (!machineConfiguration.isMultiAxisConfiguration() && currentSection.isMultiAxis()) ||
    (getPreviousSection().isMultiAxis() != currentSection.isMultiAxis()); // force newWorkPlane between indexing and simultaneous operations
  var retracted = false;
/*
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
*/

  if (insertToolCall) {
    // writeBlock("T" + toolFormat.format(tool.number) + "|" + rpmFormat.format(tool.spindleRPM) + "|" + getToolTypeName(tool.type));
    writeBlock("M" + toolFormat.format(tool.number) + ":" + xyzFormat.format(tool.diameter) + " " + getToolTypeName(tool.type) + "<" + rpmFormat.format(tool.spindleRPM) + " R.P.M>");
  }

  writeBlock("R4A00000001");

  var cuttingFeedrate;
  var entryFeedrate;
  if (currentSection.hasAnyCycle && currentSection.hasAnyCycle()) {
    cuttingFeedrate = hasParameter("operation:tool_feedPlunge") ? getParameter("operation:tool_feedPlunge") : (unit == MM ? 100 : 10);
    entryFeedrate = cuttingFeedrate;
  } else {
    cuttingFeedrate = hasParameter("operation:tool_feedCutting") ? getParameter("operation:tool_feedCutting") : (unit == MM ? 100 : 10);
    entryFeedrate = hasParameter("operation:tool_feedEntry") ? getParameter("operation:tool_feedEntry") : (unit == MM ? 100 : 10);
  }

  writeBlock("F" + feedFormat.format(cuttingFeedrate));
  writeBlock("P" + feedFormat.format(entryFeedrate));

  forceXYZ();

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("A" + xOutput.format(getCurrentPosition().x), yOutput.format(getCurrentPosition().y), zOutput.format(initialPosition.z));
    }
  }
  // writeBlock("A" + xyzFormat.format(initialPosition.x), xyzFormat.format(initialPosition.y), xyzFormat.format(initialPosition.z);
  writeBlock("A" + xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), zOutput.format(initialPosition.z));
}

function onDwell(seconds) {
  // ignore
}

function onSpindleSpeed(spindleSpeed) {
  // writeBlock(sOutput.format(tool.spindleRPM), mFormat.format(tool.clockwise ? 3 : 4));
}

function onRadiusCompensation() {
  error(localize("Radius compensation mode is not supported."));
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock("A" + x, y, z);
  }
}

function onLinear(_x, _y, _z, feed) {
  var prefix;
  switch (movement) {
  case MOVEMENT_CUTTING:
  case MOVEMENT_LINK_TRANSITION:
  case MOVEMENT_EXTENDED:
  case MOVEMENT_FINISH_CUTTING:
    prefix = "B";
    break;
  case MOVEMENT_LEAD_IN:
  case MOVEMENT_PLUNGE:
  case MOVEMENT_RAMP:
  case MOVEMENT_RAMP_HELIX:
  case MOVEMENT_RAMP_PROFILE:
  case MOVEMENT_RAMP_ZIG_ZAG:
    prefix = "C";
    break;
  case MOVEMENT_LEAD_OUT:
    prefix = "D";
    break;
  default:
    prefix = "B";
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock(prefix + x, y, z);
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  linearize(tolerance);
  return;
}

function onCommand(command) {
  // ignore
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  // writeBlock("A" + xyzFormat.format(0), xyzFormat.format(0), zFormat.format(getCurrentPosition().z));
}
