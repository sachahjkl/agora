package agoratool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are the
// toolkit's (gt:site, its `site` command); this file says what this site is: its address, names and colours.
// {{version}} in the home page is the last version: its download link names the file of that release.

import tk_site "gt:site"

VERSION_MARK :: "{{version}}"

// Where the site is published, what it is: the one place that says it.
SITE_META :: tk_site.Meta{
	url         = "https://agora.froment.software/",
	name        = "agora",
	repository  = REPOSITORY,
	tagline     = "A living world of autonomous people, watched as it runs",
	changes     = "CHANGELOG.md",
	card        = "img/card.png",
	logo        = "img/logo.png",
	logo_file   = SITE_LOGO,
	theme       = "#0e1022",
	accent      = "#f5b94a",
	author      = "Sacha Froment",
	author_url  = "https://froment.software",
	publisher   = "Froment Software",
	ld_type     = "SoftwareApplication",
	root_domain = false,   // (github.io answers for /robots.txt and /favicon.ico, not the site)
}

@(rodata)
SITE_LD := [?][2]string{
	{"applicationCategory", "SimulationApplication"},
	{"operatingSystem", "Linux"},
	{"license", "https://opensource.org/license/mit"},
}

site_meta :: proc() -> tk_site.Meta {
	m := SITE_META
	m.ld_fields = SITE_LD[:]
	return m
}
