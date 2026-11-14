package agoratool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are the
// toolkit's (gt:site, its `site` command); this file says what this site is: its address, names, colours and download.
// {{version}} in the home page is the last version: its download link names the file of that release.

import tk_site "gt:site"
import toolbox "gt:toolbox"

// Where the site is published, what it is: the one place that says it.
SITE_META :: tk_site.Meta{
	url             = "https://agora.froment.software/",
	name            = "agora",
	repository      = REPOSITORY,
	tagline         = "A living world of autonomous people, watched as it runs",
	changes         = "CHANGELOG.md",
	card            = "img/card.png",
	logo            = "img/logo.png",
	logo_file       = "site/img/logo.png",
	theme           = "#0b0d1c",
	accent          = "#f5b94a",
	author          = "Sacha Froment",
	author_url      = "https://froment.software",
	publisher       = "Froment Software",
	publisher_logo  = "img/froment-software-64.png",
	licence         = "MIT",
	ld_type         = "SoftwareApplication",
	root_domain     = false,   // (github.io answers for /robots.txt and /favicon.ico, not the site)
}

SITE_LD := [?][2]string{
	{"applicationCategory", "SimulationApplication"},
	{"operatingSystem", "Linux"},
	{"license", "https://opensource.org/license/mit"},
}

// The home page's download: the one system the release builds for.
@(rodata)
SITE_DOWNLOADS := [?]tk_site.Download{
	{os = "linux", label = "Linux", href = "https://github.com/sachahjkl/agora/releases/download/v{{version}}/agora-{{version}}-linux-x64.tar.gz", detail = "v{{version}} · x64 · .tar.gz"},
}

site_project :: proc() -> tk_site.Project_Site {
	m := SITE_META
	m.ld_fields = SITE_LD[:]
	return {meta = m, dir = "site", pages = {version_mark = "{{version}}", downloads = SITE_DOWNLOADS[:]}}
}

// The site's `site` command, as every project's tool has it.
site_command :: proc() -> toolbox.Command {
	return tk_site.command(site_project())
}
