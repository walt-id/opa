# Expects policy input as provided by:
# https://api.github.com/repos/open-policy-agent/opa/pulls/${PR_ID}/files
#
# Note that the "filename" here refers to the full path of the file, like
# docs/website/data/integrations.yaml - since that's how it's named in the
# input we'll use the same convention here.

package files

import future.keywords.in

import data.helpers.basename
import data.helpers.directory
import data.helpers.extension

filenames := {f.filename | some f in input}

logo_exts := {"png", "svg"}

changes := {filename: attributes |
	some change in input
	filename := change.filename
	attributes := object.remove(change, ["filename"])
}

get_file_in_pr(filename) = http.send({
	"url": changes[filename].raw_url,
	"method": "GET",
	"headers": {"Authorization": sprintf("Bearer %v", [opa.runtime().env.GITHUB_TOKEN])},
	"cache": true,
	"enable_redirect": true,
}).raw_body

deny["Logo must be placed in docs/website/static/img/logos/integrations"] {
	"docs/website/data/integrations.yaml" in filenames

	some filename in filenames
	extension(filename) in logo_exts
	changes[filename].status == "added"
	directory(filename) != "docs/website/static/img/logos/integrations"
}

deny["Logo must be a .png or .svg file"] {
	"docs/website/data/integrations.yaml" in filenames

	some filename in filenames
	changes[filename].status == "added"
	directory(filename) == "docs/website/static/img/logos/integrations"
	not extension(filename) in logo_exts
}

deny["Logo name must match integration"] {
	"docs/website/data/integrations.yaml" in filenames

	some filename in filenames
	ext := extension(filename)
	ext in logo_exts
	changes[filename].status == "added"
	logo_name := trim_suffix(basename(filename), concat("", [".", ext]))

	integrations := {integration | some integration, _ in yaml.unmarshal(integrations_file).integrations}
	not logo_name in integrations
}

deny[sprintf("Integration '%v' missing required attribute '%v'", [name, attr])] {
	"docs/website/data/integrations.yaml" in filenames

	file := yaml.unmarshal(integrations_file)
	required := {"title", "description"}

	some name, item in file.integrations
	some attr in (required - {key | some key, _ in item})
}

deny[sprintf("Integration '%v' references unknown software '%v' (i.e. not in 'software' object)", [name, software])] {
	"docs/website/data/integrations.yaml" in filenames

	file := yaml.unmarshal(integrations_file)
	software_list := {software | file.software[software]}

	some name, item in file.integrations
	some software in item.software
	not software in software_list
}

deny[sprintf("%s is an invalid YAML file", [filename])] {
	some filename, content in yaml_file_contents
	changes[filename].status in {"added", "modified"}
	not yaml.is_valid(content)
}

deny[sprintf("%s is an invalid JSON file", [filename])] {
	some filename, content in json_file_contents
	changes[filename].status in {"added", "modified"}
	not json.is_valid(content)
}

integrations_file := get_file_in_pr("docs/website/data/integrations.yaml")

# Helper rules to work around not being able to mock functions yet
yaml_file_contents := {filename: get_file_in_pr(filename) |
	some filename in filenames
	extension(filename) in {"yml", "yaml"}
}

json_file_contents := {filename: get_file_in_pr(filename) |
	some filename in filenames
	extension(filename) == "json"
}
