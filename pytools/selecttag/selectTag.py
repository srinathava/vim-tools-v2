#!/usr/bin/env python
from __future__ import division
from Tkinter import *
from MultiColumnTable import MultiColumnTable
from PatternEntryFrame import PatternEntryFrame
from parseTags import parseTags

class TagItem:
    def __init__(self, tag):
        self.tag = tag
        self.txt = ''

        if 'class' in tag.props:
            self.txt += (tag.props['class'] + '::')

        self.txt += tag.name

        if 'signature' in tag.props:
            self.txt += tag.props['signature']

        self.txtLower = self.txt.lower()

    def numColumns(self):
        return 2

    def columnWidth(self, colIdx):
        if colIdx == 0:
            return 2
        elif colIdx == 1:
            return 80

    def getTxt(self, colIdx):
        if colIdx == 0:
            return self.tag.type
        elif colIdx == 1:
            return self.txt

    def satisfies(self, filterTxt):
        words = filterTxt.split()
        i = 0
        for w in words:
            i = self.txtLower.find(w.lower(), i)
            if i < 0:
                return False
            i += len(w)
        return True

def main():
    top = Tk()
    top.resizable(0, 0)
    top.title('Choose a tag')

    tags = parseTags(sys.argv[1])
    ttags = []
    for t in tags:
        ttags.append(TagItem(t))

    patternEntryFrame = PatternEntryFrame(top)
    patternEntryFrame.pack(side=TOP)

    table = MultiColumnTable(top, ttags)
    table.pack(side=TOP, fill=X, expand=True)

    def filterTable(txt):
        table.refreshFilter(txt)

    def changeTableSelection(key):
        if key == 'Return':
            tag = table.getCurrentSelection().tag
            print tag.name
            print tag.file
            print tag.pattern
            top.quit()
        elif key == 'Esc':
            top.quit()
        else:
            table.moveSelection(key)

    patternEntryFrame.onChange = filterTable
    patternEntryFrame.onKeyPress = changeTableSelection

    patternEntryFrame.entry.focus()

    top.mainloop()

main()
