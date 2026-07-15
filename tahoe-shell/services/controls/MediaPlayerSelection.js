.pragma library

// Pure MPRIS active-player selection for Controls.qml.
// No QML service access; callers pass player snapshots and remembered dbus name.

function textOrEmpty(value) {
    if (value === undefined || value === null)
        return "";
    return String(value);
}

function playerDbusName(player) {
    if (!player)
        return "";
    return textOrEmpty(player.dbusName).trim();
}

function playerHasTrack(player) {
    if (!player)
        return false;
    return textOrEmpty(player.trackTitle).trim().length > 0;
}

function playerCanControl(player) {
    if (!player)
        return false;
    return !!(player.canControl
        || player.canPlay
        || player.canPause
        || player.canTogglePlaying
        || player.canGoNext
        || player.canGoPrevious
        || player.canSeek);
}

function isPlayerEligible(player) {
    if (!player)
        return false;
    // Metadata-less and uncontrollable players must not become active.
    return playerHasTrack(player) || playerCanControl(player);
}

function isPlayerPlaying(player, playingState) {
    if (!player)
        return false;
    if (player.isPlaying === true)
        return true;
    if (playingState === undefined || playingState === null)
        return false;
    return player.playbackState === playingState;
}

function collectEligiblePlayers(players) {
    var result = [];
    var list = players || [];
    for (var i = 0; i < list.length; i++) {
        if (isPlayerEligible(list[i]))
            result.push(list[i]);
    }
    return result;
}

function sortPlayersByDbusName(players) {
    var result = (players || []).slice();
    result.sort(function(left, right) {
        var leftName = playerDbusName(left);
        var rightName = playerDbusName(right);
        if (leftName < rightName)
            return -1;
        if (leftName > rightName)
            return 1;
        return 0;
    });
    return result;
}

function findPlayerByDbusName(players, dbusName) {
    var target = textOrEmpty(dbusName).trim();
    if (target.length === 0)
        return null;

    var list = players || [];
    for (var i = 0; i < list.length; i++) {
        if (playerDbusName(list[i]) === target)
            return list[i];
    }
    return null;
}

// Stable active-player selection.
//
// Priority:
// 1. Playing players (remembered if still playing; else first by dbusName).
// 2. Remembered eligible player (survives model reorder while paused).
// 3. Paused player with track (stable dbusName order).
// 4. First eligible player (stable dbusName order).
//
// playingState is the MprisPlaybackState.Playing enum value from the caller.
function selectActivePlayer(players, lastActiveDbusName, playingState) {
    var eligible = collectEligiblePlayers(players);
    if (eligible.length === 0)
        return null;

    var playing = [];
    for (var i = 0; i < eligible.length; i++) {
        if (isPlayerPlaying(eligible[i], playingState))
            playing.push(eligible[i]);
    }

    if (playing.length > 0) {
        var rememberedPlaying = findPlayerByDbusName(playing, lastActiveDbusName);
        if (rememberedPlaying)
            return rememberedPlaying;
        return sortPlayersByDbusName(playing)[0];
    }

    var remembered = findPlayerByDbusName(eligible, lastActiveDbusName);
    if (remembered)
        return remembered;

    var pausedWithTrack = [];
    for (var j = 0; j < eligible.length; j++) {
        if (playerHasTrack(eligible[j]))
            pausedWithTrack.push(eligible[j]);
    }
    if (pausedWithTrack.length > 0)
        return sortPlayersByDbusName(pausedWithTrack)[0];

    return sortPlayersByDbusName(eligible)[0];
}
