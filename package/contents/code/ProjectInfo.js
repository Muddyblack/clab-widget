// Shared project links, release checks and statistics for CLAB Widget.
.pragma library

var name = "CLAB Widget";
var author = "muddyblack";
var repository = "https://github.com/Muddyblack/clab-widget";
var profile = "https://github.com/Muddyblack";
var avatar = "https://github.com/Muddyblack.png?size=128";
var license = "GPL-3.0";
var licenseId = "GPL-3.0-or-later";
var currentVersion = "0.1.0";
var latestReleaseUrl = "https://api.github.com/repos/Muddyblack/clab-widget/releases/latest";
var releasesPage = repository + "/releases";
var contributorsUrl = "https://api.github.com/repos/Muddyblack/clab-widget/contributors?per_page=12";
var contributorsPage = repository + "/graphs/contributors";

var statistics = [
    {id: "stars", label: "GitHub stars", icon: "star.svg", href: repository + "/stargazers", url: "https://img.shields.io/github/stars/Muddyblack/clab-widget.json"},
    {id: "downloads", label: "GitHub downloads", icon: "download.svg", href: repository + "/releases", url: "https://img.shields.io/github/downloads/Muddyblack/clab-widget/total.json"}
];

var references = [
    {
        id: "containerlab",
        name: "Containerlab",
        by: "srl-labs / Nokia",
        desc: "Orchestrate container-based network labs",
        url: "https://containerlab.dev",
        repo: "https://github.com/srl-labs/containerlab",
        icon: "containerlab.svg"
    },
    {
        id: "netlab",
        name: "netlab",
        by: "Ivan Pepelnjak / ipSpace.net",
        desc: "Automate network lab orchestration and configuration",
        url: "https://netlab.tools",
        repo: "https://ipspace.net",
        icon: "netlab.svg"
    }
];

function count(text) {
    try {
        var badge = JSON.parse(text);
        var value = String(badge.value === undefined ? "" : badge.value).trim();
        return !badge.isError && /^\d[\d,. ]*[kmbt]?\+?$/i.test(value) ? value : "";
    } catch (error) { return ""; }
}

function contributors(text) {
    try {
        var response = JSON.parse(text);
        if (!Array.isArray(response)) return [];
        return response.filter(function (entry) {
            return entry && entry.type !== "Bot" && typeof entry.login === "string"
                && /^[A-Za-z0-9-]{1,39}$/.test(entry.login)
                && Number.isFinite(entry.contributions) && entry.contributions > 0;
        }).slice(0, 12).map(function (entry) {
            return {
                login: entry.login,
                commits: entry.contributions,
                profile: "https://github.com/" + entry.login,
                avatar: "https://github.com/" + entry.login + ".png?size=96"
            };
        });
    } catch (error) { return []; }
}

function parseVersion(value) {
    if (typeof value !== "string") return null;
    var match = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/.exec(value);
    return match ? {numbers: [Number(match[1]), Number(match[2]), Number(match[3])], prerelease: match[4] || ""} : null;
}

// Compare against a stable release; a prerelease of the same version is older.
function releaseStatus(current, latest) {
    var local = parseVersion(current), remote = parseVersion(latest);
    if (!local || !remote || remote.prerelease) return "Version comparison unavailable";
    for (var i = 0; i < 3; i++) {
        if (local.numbers[i] < remote.numbers[i]) return "Update available";
        if (local.numbers[i] > remote.numbers[i]) return "Newer than latest release";
    }
    return local.prerelease ? "Update available" : "Up to date";
}

function releaseVersion(text) {
    try {
        var release = JSON.parse(text);
        if (!release || release.draft || release.prerelease) return "";
        var parsed = parseVersion(release.tag_name);
        return parsed && !parsed.prerelease ? release.tag_name.replace(/^v/, "") : "";
    } catch (error) { return ""; }
}
