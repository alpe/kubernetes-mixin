{
  prometheusRules+:: {
    groups+: [
      {
        name: 'k8s.rules',
        rules: [
          {
            record: 'namespace:container_cpu_usage_seconds_total:sum_rate',
            expr: |||
              label_replace(sum(rate(container_cpu_usage_seconds_total{%(cadvisorSelector)s, image!=""}[5m])) by (namespace), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
          {
            record: 'namespace:container_memory_usage_bytes:sum',
            expr: |||
              label_replace(sum(container_memory_usage_bytes{%(cadvisorSelector)s, image!=""}) by (namespace), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
          {
            record: 'namespace_name:container_cpu_usage_seconds_total:sum_rate',
            expr: |||
              label_replace(sum by (namespace, label_name) (
                 sum(rate(container_cpu_usage_seconds_total{%(cadvisorSelector)s, image!=""}[5m])) by (namespace, pod_name)
               * on (namespace, pod_name) group_left(label_name)
                 label_replace(kube_pod_labels{%(kubeStateMetricsSelector)s}, "pod_name", "$1", "pod", "(.*)")
              ), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
          {
            record: 'namespace_name:container_memory_usage_bytes:sum',
            expr: |||
              label_replace(sum by (namespace, label_name) (
                sum(container_memory_usage_bytes{%(cadvisorSelector)s,image!=""}) by (pod_name, namespace)
              * on (namespace, pod_name) group_left(label_name)
                label_replace(kube_pod_labels{%(kubeStateMetricsSelector)s}, "pod_name", "$1", "pod", "(.*)")
              ), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
          {
            record: 'namespace_name:kube_pod_container_resource_requests_memory_bytes:sum',
            expr: |||
              label_replace(sum by (namespace, label_name) (
                sum(kube_pod_container_resource_requests_memory_bytes{%(kubeStateMetricsSelector)s}) by (namespace, pod)
              * on (namespace, pod) group_left(label_name)
                label_replace(kube_pod_labels{%(kubeStateMetricsSelector)s}, "pod_name", "$1", "pod", "(.*)")
              ), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
          {
            record: 'namespace_name:kube_pod_container_resource_requests_cpu_cores:sum',
            expr: |||
              label_replace(sum by (namespace, label_name) (
                sum(kube_pod_container_resource_requests_cpu_cores{%(kubeStateMetricsSelector)s} and on(pod) kube_pod_status_scheduled{condition="true"}) by (namespace, pod)
              * on (namespace, pod) group_left(label_name)
                label_replace(kube_pod_labels{%(kubeStateMetricsSelector)s}, "pod_name", "$1", "pod", "(.*)")
              ), "%(namespaceLabel)s", "$1", "namespace", "(.*)")
            ||| % $._config,
          },
        ],
      },
      {
        name: 'kube-apiserver.rules',
        rules: [
          {
            record: 'cluster_quantile:apiserver_request_latencies:histogram_quantile',
            expr: |||
              histogram_quantile(%(quantile)s, sum(rate(apiserver_request_latencies_bucket{%(kubeApiserverSelector)s}[5m])) without(instance, %(podLabel)s)) / 1e+06
            ||| % ({ quantile: quantile } + $._config),
            labels: {
              quantile: quantile,
            },
          }
          for quantile in ['0.99', '0.9', '0.5']
        ],
      },
      {
        name: 'node.rules',
        rules: [
          {
            // Number of nodes in the cluster
            // SINCE 2018-02-08
            record: ':kube_pod_info_node_count:',
            expr: 'sum(min(kube_pod_info) by (node))',
          },
          {
            // This rule results in the tuples (node, namespace, instance) => 1;
            // it is used to calculate per-node metrics, given namespace & instance.
            record: 'node_namespace_pod:kube_pod_info:',
            expr: |||
              max(label_replace(kube_pod_info{%(kubeStateMetricsSelector)s}, "%(podLabel)s", "$1", "pod", "(.*)")) by (node, %(namespaceLabel)s, %(podLabel)s)
            ||| % $._config,
          },
          {
            // This rule gives the number of CPUs per node.
            record: 'node:node_num_cpu:sum',
            expr: |||
              count by (node) (sum by (node, cpu) (
                node_cpu_seconds_total{%(nodeExporterSelector)s}
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              ))
            ||| % $._config,
          },
          {
            // CPU utilisation is % CPU is not idle.
            record: ':node_cpu_utilisation:avg1m',
            expr: |||
              1 - avg(rate(node_cpu_seconds_total{%(nodeExporterSelector)s,mode="idle"}[1m]))
            ||| % $._config,
          },
          {
            // CPU utilisation is % CPU is not idle.
            record: 'node:node_cpu_utilisation:avg1m',
            expr: |||
              1 - avg by (node) (
                rate(node_cpu_seconds_total{%(nodeExporterSelector)s,mode="idle"}[1m])
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:)
            ||| % $._config,
          },
          {
            // CPU saturation is 1min avg run queue length / number of CPUs.
            // Can go over 100%.  >100% is bad.
            record: ':node_cpu_saturation_load1:',
            expr: |||
              sum(node_load1{%(nodeExporterSelector)s})
              /
              sum(node:node_num_cpu:sum)
            ||| % $._config,
          },
          {
            // CPU saturation is 1min avg run queue length / number of CPUs.
            // Can go over 100%.  >100% is bad.
            record: 'node:node_cpu_saturation_load1:',
            expr: |||
              sum by (node) (
                node_load1{%(nodeExporterSelector)s}
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
              /
              node:node_num_cpu:sum
            ||| % $._config,
          },
          {
            record: ':node_memory_utilisation:',
            expr: |||
              1 -
              sum(node_memory_MemFree_bytes{%(nodeExporterSelector)s} + node_memory_Cached_bytes{%(nodeExporterSelector)s} + node_memory_Buffers_bytes{%(nodeExporterSelector)s})
              /
              sum(node_memory_MemTotal_bytes{%(nodeExporterSelector)s})
            ||| % $._config,
          },
          {
            // Available memory per node
            // SINCE 2018-02-08
            record: 'node:node_memory_bytes_available:sum',
            expr: |||
              sum by (node) (
                (node_memory_MemFree_bytes{%(nodeExporterSelector)s} + node_memory_Cached_bytes{%(nodeExporterSelector)s} + node_memory_Buffers_bytes{%(nodeExporterSelector)s})
                * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                  node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            // Total memory per node
            // SINCE 2018-02-08
            record: 'node:node_memory_bytes_total:sum',
            expr: |||
              sum by (node) (
                node_memory_MemTotal_bytes{%(nodeExporterSelector)s}
                * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                  node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            // Memory utilisation per node, normalized by per-node memory
            // NEW 2018-02-08
            record: 'node:node_memory_utilisation:ratio',
            expr: |||
              (node:node_memory_bytes_total:sum - node:node_memory_bytes_available:sum)
              /
              scalar(sum(node:node_memory_bytes_total:sum))
            |||,
          },
          {
            record: ':node_memory_swap_io_bytes:sum_rate',
            expr: |||
              1e3 * sum(
                (rate(node_vmstat_pgpgin{%(nodeExporterSelector)s}[1m])
               + rate(node_vmstat_pgpgout{%(nodeExporterSelector)s}[1m]))
              )
            ||| % $._config,
          },
          {
            // DEPRECATED
            record: 'node:node_memory_utilisation:',
            expr: |||
              1 -
              sum by (node) (
                (node_memory_MemFree_bytes{%(nodeExporterSelector)s} + node_memory_Cached_bytes{%(nodeExporterSelector)s} + node_memory_Buffers_bytes{%(nodeExporterSelector)s})
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
              /
              sum by (node) (
                node_memory_MemTotal_bytes{%(nodeExporterSelector)s}
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            // DEPENDS 2018-02-08
            // REPLACE node:node_memory_utilisation:
            record: 'node:node_memory_utilisation_2:',
            expr: |||
              1 - (node:node_memory_bytes_available:sum / node:node_memory_bytes_total:sum)
            ||| % $._config,
          },
          {
            record: 'node:node_memory_swap_io_bytes:sum_rate',
            expr: |||
              1e3 * sum by (node) (
                (rate(node_vmstat_pgpgin{%(nodeExporterSelector)s}[1m])
               + rate(node_vmstat_pgpgout{%(nodeExporterSelector)s}[1m]))
               * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                 node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            // Disk utilisation (ms spent, by rate() it's bound by 1 second)
            record: ':node_disk_utilisation:avg_irate',
            expr: |||
              avg(irate(node_disk_io_time_seconds_total{%(nodeExporterSelector)s,device=~"(sd|xvd).+"}[1m]))
            ||| % $._config,
          },
          {
            // Disk utilisation (ms spent, by rate() it's bound by 1 second)
            record: 'node:node_disk_utilisation:avg_irate',
            expr: |||
              avg by (node) (
                irate(node_disk_io_time_seconds_total{%(nodeExporterSelector)s,device=~"(sd|xvd).+"}[1m])
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            // Disk saturation (ms spent, by rate() it's bound by 1 second)
            record: ':node_disk_saturation:avg_irate',
            expr: |||
              avg(irate(node_disk_io_time_weighted_seconds_total{%(nodeExporterSelector)s,device=~"(sd|xvd).+"}[1m]))
            ||| % $._config,
          },
          {
            // Disk saturation (ms spent, by rate() it's bound by 1 second)
            record: 'node:node_disk_saturation:avg_irate',
            expr: |||
              avg by (node) (
                irate(node_disk_io_time_weighted_seconds_total{%(nodeExporterSelector)s,device=~"(sd|xvd).+"}[1m])
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            record: ':node_net_utilisation:sum_irate',
            expr: |||
              sum(irate(node_network_receive_bytes_total{%(nodeExporterSelector)s,device="eth0"}[1m])) +
              sum(irate(node_network_transmit_bytes_total{%(nodeExporterSelector)s,device="eth0"}[1m]))
            ||| % $._config,
          },
          {
            record: 'node:node_net_utilisation:sum_irate',
            expr: |||
              sum by (node) (
                (irate(node_network_receive_bytes_total{%(nodeExporterSelector)s,device="eth0"}[1m]) +
                irate(node_network_transmit_bytes_total{%(nodeExporterSelector)s,device="eth0"}[1m]))
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
          {
            record: ':node_net_saturation:sum_irate',
            expr: |||
              sum(irate(node_network_receive_drop_total{%(nodeExporterSelector)s,device="eth0"}[1m])) +
              sum(irate(node_network_transmit_drop_total{%(nodeExporterSelector)s,device="eth0"}[1m]))
            ||| % $._config,
          },
          {
            record: 'node:node_net_saturation:sum_irate',
            expr: |||
              sum by (node) (
                (irate(node_network_receive_drop_total{%(nodeExporterSelector)s,device="eth0"}[1m]) +
                irate(node_network_transmit_drop_total{%(nodeExporterSelector)s,device="eth0"}[1m]))
              * on (%(namespaceLabel)s, %(podLabel)s) group_left(node)
                node_namespace_pod:kube_pod_info:
              )
            ||| % $._config,
          },
        ],
      },
    ],
  },
}
