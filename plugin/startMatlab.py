#!/usr/bin/env python

from __future__ import print_function
import re, time
import subprocess
import sys
try:
    from subprocess import getoutput
except ImportError:
    from commands import getoutput

def startMatlab(extraArgs):
    if ('-nojvm' in extraArgs) or ('-nodesktop' in extraArgs):
        useXterm = True
    else:
        useXterm = False

    extraArgs = extraArgs.split()
    if useXterm:
        pid = subprocess.Popen(['xterm', '-e', 'sb', '-skip-sb-startup-checks'] + extraArgs).pid
    else:
        pid = subprocess.Popen(['sb', '-skip-sb-startup-checks'] + extraArgs).pid

    # wait for the correct MATLAB process to be loaded.
    n = 0
    while 1:
        pst = getoutput('pstree -p %d' % pid)
        m = re.search(r'MATLAB\((\d+)\)', pst)
        if m:
            return int(m.group(1))

        time.sleep(0.5)
        n += 1
        if n == 10:
            return 0

if __name__ == "__main__":
    pid = startMatlab(' '.join(sys.argv[1:]))
    print(pid)

