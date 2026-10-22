package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"text/template"
)

// fetchBrowserConfigFromTF retrieves browser monitoring metadata from Terraform outputs.
func fetchBrowserConfigFromTF(tfArgs []string, env []string, cfg *Config) {
	cmd := exec.Command("terraform", append(tfArgs, "output", "-json", "browser_js_config")...)
	cmd.Env = env
	out, _ := cmd.Output()

	var tfOutput string
	json.Unmarshal(out, &tfOutput)
	var nrConfig BrowserConfig
	json.Unmarshal([]byte(tfOutput), &nrConfig)

	cmdKey := exec.Command("terraform", append(tfArgs, "output", "-raw", "browser_license_key")...)
	cmdKey.Env = env
	outKey, _ := cmdKey.Output()

	cfg.BrowserLicenseKey = strings.TrimSpace(string(outKey))
	cfg.BrowserAppID = formatID(nrConfig.Info.AppID)
	cfg.BrowserAccountID = formatID(nrConfig.LoaderConfig.AccountID)
	cfg.BrowserTrustKey = formatID(nrConfig.LoaderConfig.TrustKey)
	cfg.BrowserAgentID = formatID(nrConfig.LoaderConfig.AgentID)
}

// generateBrowserYaml populates the nr-browser.yaml file using a template.
func generateBrowserYaml(cfg *Config) {
	data := TemplateData{
		LicenseKey: cfg.BrowserLicenseKey,
		AppID:      cfg.BrowserAppID,
		AccountID:  cfg.BrowserAccountID,
		TrustKey:   cfg.BrowserTrustKey,
		AgentID:    cfg.BrowserAgentID,
	}

	yamlPath := Paths["otel-browser-values"]
	tmpl, err := template.ParseFiles(yamlPath + ".tmpl")
	if err != nil {
		fmt.Printf("Error: Template file not found at %s.tmpl\n", yamlPath)
		return
	}
	outFile, _ := os.Create(yamlPath)
	defer outFile.Close()
	tmpl.Execute(outFile, data)
}

// handleK8s manages the Kubernetes installation, upgrade, and uninstallation workflows.
func handleK8s(action string, cfg *Config) {
	checkTools("kubectl", "helm")
	ns := Charts["otel-demo"].NS

	if action == "uninstall" {
		collector := uninstallCollector(ns)
		for _, key := range []string{"otel-demo", collector} {
			if helmReleaseExists(Charts[key].Name, ns) {
				runCommand("helm", []string{"uninstall", Charts[key].Name, "-n", ns}, nil)
			} else {
				fmt.Printf("Release '%s' is not installed in namespace '%s'; skipping.\n", Charts[key].Name, ns)
			}
		}
		if out, err := exec.Command("helm", "list", "-n", ns, "-q").Output(); err == nil && strings.TrimSpace(string(out)) == "" {
			runCommand("kubectl", []string{"delete", "ns", ns}, nil)
		} else {
			fmt.Printf("Other Helm releases remain in namespace '%s'; keeping the namespace.\n", ns)
		}
		return
	}

	// Browser setup logic: executes only if enabled and config is missing
	if cfg.EnableBrowser != nil && *cfg.EnableBrowser {
		if cfg.BrowserAppID == "" {
			fmt.Println("\n>>> Setting up Browser Monitoring (Terraform)...")
			oldTarget := cfg.Target
			cfg.Target = "browser"
			handleTerraform("install", cfg)
			cfg.Target = oldTarget
			generateBrowserYaml(cfg)
		} else {
			generateBrowserYaml(cfg)
		}
	}

	runCommand("helm", []string{"repo", "add", "newrelic", "https://helm-charts.newrelic.com"}, nil)
	runCommand("helm", []string{"repo", "add", "open-telemetry", "https://open-telemetry.github.io/opentelemetry-helm-charts"}, nil)
	runCommand("helm", []string{"repo", "update", "newrelic", "open-telemetry"}, nil)

	detectOpenShift()
	exec.Command("kubectl", "create", "ns", ns).Run()

	exec.Command("kubectl", "delete", "secret", "newrelic-license-key", "-n", ns).Run()
	runCommand("kubectl", []string{"create", "secret", "generic", "newrelic-license-key", "--from-literal=license-key=" + cfg.LicenseKey, "--from-literal=otlp-endpoint=" + otlpEndpointForRegion(cfg.Region), "-n", ns}, nil)

	if k8sCollector() == "kube-stack" {
		installChart("kube-stack", []string{Paths["kube-stack-values"]}, "clusterName="+OtelDemoNamespace, "opentelemetry-operator.admissionWebhooks.certManager.enabled=false", "opentelemetry-operator.admissionWebhooks.autoGenerateCert.enabled=true")

		otelValues := []string{Paths["otel-values"], Paths["kube-stack-overlay"]}
		if cfg.EnableBrowser != nil && *cfg.EnableBrowser {
			otelValues = append(otelValues, Paths["otel-browser-values"])
		}
		installChart("otel-demo", otelValues)
	} else {
		installChart("nr-k8s", []string{Paths["nr-k8s-values"]}, "global.region="+strings.ToLower(cfg.Region))

		otelValues := []string{Paths["otel-values"]}
		if cfg.EnableBrowser != nil && *cfg.EnableBrowser {
			otelValues = append(otelValues, Paths["otel-browser-values"])
		}
		installChart("otel-demo", otelValues)
	}
}

// k8sCollector returns the collector chart selected by K8S_COLLECTOR, defaulting to nr-k8s.
func k8sCollector() string {
	if c := os.Getenv("K8S_COLLECTOR"); c != "" {
		return c
	}
	return "nr-k8s"
}

// helmReleaseExists reports whether a Helm release is installed in the namespace.
func helmReleaseExists(name, ns string) bool {
	return exec.Command("helm", "status", name, "-n", ns).Run() == nil
}

// uninstallCollector picks the collector release to remove: K8S_COLLECTOR when
// set, otherwise whichever one is installed, asking only if both are.
func uninstallCollector(ns string) string {
	if os.Getenv("K8S_COLLECTOR") != "" {
		return normalizeCollector(os.Getenv("K8S_COLLECTOR"))
	}
	nr := helmReleaseExists(Charts["nr-k8s"].Name, ns)
	ks := helmReleaseExists(Charts["kube-stack"].Name, ns)
	switch {
	case ks && !nr:
		return "kube-stack"
	case nr && ks:
		fmt.Println("\n>>> Both collectors are installed.")
		fmt.Println("  1. nr-k8s-otel-collector")
		fmt.Println("  2. opentelemetry-kube-stack")
		return normalizeCollector(promptUser("Choose the collector to uninstall (1 or 2)", validateCollectorChoice))
	}
	return "nr-k8s"
}

// otlpEndpointForRegion returns the New Relic OTLP endpoint for a region.
func otlpEndpointForRegion(region string) string {
	switch strings.ToLower(region) {
	case "eu":
		return "https://otlp.eu01.nr-data.net"
	case "jp":
		return "https://otlp.jp.nr-data.net"
	}
	return "https://otlp.nr-data.net"
}

// installChart executes the helm upgrade --install command for a given chart.
func installChart(key string, values []string, extraSets ...string) {
	c := Charts[key]
	args := []string{"upgrade", "--install", c.Name, c.Repo, "--version", c.Version, "-n", c.NS}
	for _, v := range values {
		args = append(args, "-f", v)
	}
	for _, s := range extraSets {
		args = append(args, "--set", s)
	}

	if isOpenShift {
		if key == "nr-k8s" {
			args = append(args, "--set", "provider=OPEN_SHIFT")
		}
		if key == "otel-demo" {
			args = append(args, "--set", "serviceAccount.create=false", "--set", "serviceAccount.name="+c.NS)
		}
	}
	runCommand("helm", args, nil)
}

// detectOpenShift checks the cluster for OpenShift-specific API versions.
func detectOpenShift() {
	out, err := exec.Command("kubectl", "api-versions").Output()
	if err == nil && strings.Contains(string(out), "security.openshift.io") {
		isOpenShift = true
		fmt.Println("OpenShift detected.")
	}
}
