import QtQuick
import QtQuick.Controls
import MuseScore

MuseScore {
	description: "Pitch Cleaner with Tie Merging and Extra Sign Removal"
	version: "1.0"
	title: "Pitch Cleaner"
	thumbnailName: ""
	categoryCode: "composing-arranging-tools"
	pluginType: "dialog"
	width: 400
	height: 200
	Rectangle {
		id: ctrlRectangle
		width: 400
		height: 200
		color: "#9668a0"
		MessageDialog {
			id: ctrlMessageDialog
			title: "Pitch Cleaner Message"
			text: ""
			visible: false
			onAccepted: ctrlMessageDialog.close()
		}
	}
	onRun: {
		optimizeNotes();
	}
	function msg(msg) {
		ctrlMessageDialog.text = msg;
		ctrlMessageDialog.visible = true;
	}
	function deleteElement(elementToRemove) {
		try {
			if( elementToRemove.type === Element.NOTE ){
				var note = elementToRemove;
				var misc = note.elements;
				var chord = note.parent;
				if( chord.notes.length <= 1 ){
					var par = chord.parent;

					curScore.startCmd();
					par.remove(chord);
					removeElement(chord);
					curScore.endCmd();
				} else {
					for( var i = 0 ; i < misc.length ; i++ ){
						curScore.startCmd();
						note.remove(misc[i]);
						//removeElement(misc[i]);
						curScore.endCmd();
					}
					curScore.startCmd();
					chord.remove(elementToRemove);
					//removeElement(elementToRemove);
					curScore.endCmd();
				}
			} else {
				var par = elementToRemove.parent;

				curScore.startCmd();
				par.remove(elementToRemove);
				//removeElement(elementToRemove);
				curScore.endCmd();
			}
		} catch(e) { }
	}
	function mergeTiedNotes(notes, staffIdx) {
		var ties = {};
		var tiesTickLen = {};

		for (var i = 0; i < notes.length; i++) {
			var note = notes[i];
			var elem = note['element'];
			if (!elem.tieBack && !elem.tieForward) {
				continue;
			}
			elem = elem.firstTiedNote;
			var tick = getParent("SEGMENT",elem).tick;
			if (ties[tick]) {
				continue;
			}
			ties[tick] = [elem];
			while (elem.tieForward) {
				elem = elem.tieForward.endNote;
				ties[tick].push(elem);
			}
			var seg = getParent('SEGMENT', elem);
			var nextSeg = seg ? seg.next : null;
			var ticksLen = 0;
			if (!nextSeg){
				ticksLen = (curScore.lastSegment.tick + 1) - tick;
			} else {
				ticksLen = nextSeg.tick - tick;
			}
			tiesTickLen[tick] = ticksLen;
		}

		var cursor = curScore.newCursor();
		cursor.staffIdx = staffIdx;

		for (var tick in ties) {

			if (ties.hasOwnProperty(tick)){
				var tieNotes = ties[tick];

				if (tieNotes.length > 1) {
					var firstNote = tieNotes[0];

					var dur = 1920 / tiesTickLen[tick];

					cursor.rewindToTick(tick);
					cursor.voice = firstNote.voice;
					cursor.setDuration(1, dur);

					for( var i = tieNotes.length - 1 ; i >= 0 ; i-- ){
						deleteElement(tieNotes[i]);
					}

					curScore.startCmd();
					cursor.addNote(firstNote.pitch, true);
					curScore.endCmd();
				}
			}
		}
	}
	function groupNotes(notes, tickTolerance, groups) {
		for (var i = 0; i < notes.length; i++) {
			var note = notes[i];
			var inExistingGroup = false;
			for (var j = 0; j < groups.length; j++) {
				var group = groups[j];
				for (var k = 0; k < group.length; k++) {
					var groupNote = group[k];
					if (Math.abs(note.pitchClass - groupNote.pitchClass) <= 2 && Math.abs(note.tick - groupNote.tick) <= tickTolerance) {
						group.push(note);
						inExistingGroup = true;
						break;
					}
				}
				if (inExistingGroup) {
					break;
				}
			}
			if (!inExistingGroup) {
				var newGroup = [note];
				for (var j = i + 1; j < notes.length; j++) {
					var otherNote = notes[j];
					if (Math.abs(note.pitchClass - otherNote.pitchClass) <= 2 && Math.abs(note.tick - otherNote.tick) <= tickTolerance) {
						newGroup.push(otherNote);
					}
				}
				if (newGroup.length > 1){
					groups.push(newGroup);
				}
			}
		}
	}
	function getParent(tp, e) {

		while (e && e.type !== Element[tp]) {
			e = e.parent;
		}

		return e.type === Element[tp] ? e : null;
	}
	function optimizeNotes() {
		msg('Optimization is running');
		var tickTolerance = 240;

		if (!curScore.selection.isRange) {
			curScore.startCmd();
			curScore.selection.clear();
			curScore.endCmd();

			curScore.startCmd();
			curScore.selection.selectRange(0, curScore.lastSegment.tick, 0, curScore.staves.length);
			curScore.endCmd();
		}

		var startStaff = curScore.selection.startStaff;
		var endStaff = curScore.selection.endStaff;

		var staffs = endStaff - startStaff;

		var startSeg = curScore.selection.startSegment;
		var endSeg = curScore.selection.endSegment;

		var removedCount = [0];

		for( var staffIdx = startStaff; staffIdx < endStaff; staffIdx++ ){
			updateStaff(staffIdx, startSeg, endSeg, removedCount, tickTolerance);
		}

		curScore.startCmd();
		curScore.selection.clear();
		curScore.endCmd();

		curScore.startCmd();
		curScore.selection.selectRange(startSeg.tick, endSeg.tick, startStaff, endStaff);
		curScore.endCmd();

		msg('Finished. Removed ' + removedCount[0] + ' notes');
	}
	function refreshNotes(notes, groups, elements, tickTolerance, staffIdx, startSeg, endSeg){

		curScore.startCmd();
		curScore.selection.clear();
		curScore.endCmd();

		curScore.startCmd();
		curScore.selection.selectRange(startSeg.tick, endSeg.tick, staffIdx, staffIdx + 1);
		curScore.endCmd();

		var es = curScore.selection.elements;
		for(var i = 0 ; i < es.length ; i++){
			elements.push(es[i]);
		}

		for (var i = 0; i < elements.length; i++) {
			var elem = elements[i];
			if (elem && elem.pitch) {
				notes.push({
					element: elem,
					tick: getParent("SEGMENT",elem).tick,
					pitch: elem.pitch,
					pitchClass: elem.pitch % 12,
					octave: Math.floor(elem.pitch / 12)
				});
			}
		}

		groupNotes(notes, tickTolerance, groups);
	}
	function updateStaff(staffIdx, startSeg, endSeg, removedCount, tickTolerance) {

		var elements = [];
		var notes = [];
		var groups = [];
		refreshNotes(notes,groups,elements,tickTolerance,staffIdx,startSeg,endSeg);

		try {
			mergeTiedNotes(notes, staffIdx);
		} catch(e) {
			msg(e.message);
		}

		elements = [];
		notes = [];
		groups = [];
		refreshNotes(notes,groups,elements,tickTolerance,staffIdx,startSeg,endSeg);

		try {
			for (var i = 0; i < groups.length; i++) {
				var group = groups[i];
				group.sort(function (a, b) {
					if (b.octave !== a.octave) {
						return b.octave - a.octave;
					} else {
						return b.pitch - a.pitch;
					}
				});
				var badO = [0,1,2,8,9,10];
				var safeO = [];
				var safeP = [];
				for (var j = 0; j < group.length; j++) {
					var o = group[j].octave;
					var p = group[j].pitchClass;
					if(badO.includes(o) || safeO.includes(o) || safeP.includes(p)){
						deleteElement(group[j].element);
						removedCount[0] = removedCount[0] + 1;
					}
					safeO.push(o);
					safeP.push(p);
				}
			}
		} catch(e) {
			msg(e.message);
		}

		elements = [];
		notes = [];
		groups = [];
		refreshNotes(notes,groups,elements,tickTolerance,staffIdx,startSeg,endSeg);

		try {
			var maxOct = 6;
			var minOct = 4;
			for (var i = 0; i < notes.length; i++) {
				var note = notes[i];
				if(note.octave < minOct){
					var octsDiff = minOct - note.octave;

					curScore.startCmd();
					note.element.pitch = octsDiff*12 + note.pitch;
					curScore.endCmd();
				} else if(note.octave > maxOct){
					var octsDiff = maxOct - note.octave;

					curScore.startCmd();
					note.element.pitch = octsDiff*12 + note.pitch;
					curScore.endCmd();
				}
			}
		} catch(e) {
			msg(e.message);
		}

		elements = [];
		notes = [];
		groups = [];
		refreshNotes(notes,groups,elements,tickTolerance,staffIdx,startSeg,endSeg);

		for (var i = 0; i < elements.length; i++) {
			try {
				var tk = getParent("SEGMENT",elements[i]).tick;
				if( elements[i].type === Element.CLEF && (tk % 1920) > 1 ){
					deleteElement(elements[i]);
				} else if( elements[i].type === Element.REST ){
					deleteElement(elements[i]);
				} else if( elements[i].type === Element.TIE ){
					deleteElement(elements[i]);
				}
			} catch(e) { }
		}
	}
}
