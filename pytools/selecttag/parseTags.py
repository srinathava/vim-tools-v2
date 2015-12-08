import re
from operator import attrgetter

PAT_TAG_PATTERN = re.compile(r'(.*);"\t(.*)')

class Tag:
    def __init__(self, line):
        (self.name, self.file, rest) = line.split('\t', 2)

        m = PAT_TAG_PATTERN.match(rest)
        self.pattern = m.group(1)
        rest = m.group(2)

        self.location = self.file + '\t' + self.pattern

        self.type = rest[0]
        rest = rest[2:]

        self.props = {}
        if rest:
            for it in rest.split('\t'):
                (name, value) = it.split(':', 1)
                self.props[name] = value

def parseTags(fname):
    loc2TagMap = {}
    tags = []
    for line in open(fname):
        if not line.startswith('!'):
            t = Tag(line)
            if t.type == 'n':
                continue
            if t.location in loc2TagMap:
                prevT = loc2TagMap[t.location]
                if t.name > prevT.name:
                    loc2TagMap[t.location] = t
            else:
                loc2TagMap[t.location] = t

    tags = loc2TagMap.values()
    tags.sort(key=attrgetter('name'))
    return tags

if __name__ == "__main__":
    tags = parseTags('stateflow.inc.tags')
    print len(tags)
    for i in range(5000):
        print tags[i].name

