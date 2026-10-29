"""Filter a multi-document `helm template` stream: drop what must not be committed or applied.

Reads stdin, writes stdin minus the dropped kinds to stdout.

  Secret        the chart generates credentials at render time (see the Makefile)
  StorageClass  the chart renders an IBM Cloud VPC one (vpc.block.csi.ibm.io) that no PVC
                uses; cluster-scoped, and meaningless on this AWS/EBS cluster
"""
import re
import sys

DROP = re.compile(r"(?m)^kind: (Secret|StorageClass)\s*$")

docs = re.split(r"(?m)^---\s*$", sys.stdin.read())
kept = [d for d in docs if d.strip() and not DROP.search(d)]
sys.stdout.write("".join("---" + d for d in kept))
