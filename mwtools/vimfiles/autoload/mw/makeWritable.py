import os, stat

def makeWritable(fileName):
    filePerms = os.stat(fileName).st_mode | stat.S_IWUSR
    os.chmod(fileName, filePerms)
