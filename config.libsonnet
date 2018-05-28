{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.
    cadvisorSelector: 'job="kubernetes-cadvisor"',
    kubeletSelector: 'job="kubernetes-nodes"',
    kubeStateMetricsSelector: 'app="kube-state-metrics",component="core",job="kubernetes-service-endpoints"',
    nodeExporterSelector: 'app="prometheus",component="node-exporter"',
    notKubeDnsSelector: 'job!="kube-dns"',
    kubeApiserverSelector: 'job="kubernetes-apiservers"',
    podLabel: 'kubernetes_pod_name',
    namespaceLabel: 'kubernetes_namespace',

    // We build alerts for the presence of all these jobs.
    jobs: {
      Kubelet: $._config.kubeletSelector,
      KubeAPI: $._config.kubeApiserverSelector,
    },

    // We alert when the aggregate (CPU, Memory) quota for all namespaces is
    // greater than the amount of the resources in the cluster.  We do however
    // allow you to overcommit if you wish.
    namespaceOvercommitFactor: 1.5,
    kubeletTooManyPods: 100,
    certExpirationWarningSeconds: 7 * 24 * 3600,
    certExpirationCriticalSeconds: 1 * 24 * 3600,

    // For links between grafana dashboards, you need to tell us if your grafana
    // servers under some non-root path.
    grafanaPrefix: '',
  },
}
