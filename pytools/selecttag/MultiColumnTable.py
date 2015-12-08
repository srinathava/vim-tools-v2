from __future__ import division
from Tkinter import *

NUM_LINES_TO_SHOW = 20

class MultiColumnTable(Frame):
    def __init__(self, parent, items, filterTxt=''):
        Frame.__init__(self, parent)

        self.allItems = items
        self.filteredItems = items
        self.filterTxt = ''

        self.currentOffset = 0
        self.currentSelectionIdx = 0

        self.numRowsShown = -1

        self.numColumns = items[0].numColumns()

        self.listBoxes = []
        for i in range(self.numColumns):
            listBox = Listbox(self, height=NUM_LINES_TO_SHOW,
                    exportselection=False, width=items[0].columnWidth(i))
            listBox.pack(side=LEFT, fill=X)
            self.listBoxes.append(listBox)

        self.scrollBar = Scrollbar(self, orient=VERTICAL)
        self.scrollBar.pack(side=LEFT, fill=Y)

        self.scrollBar['command'] = self.scrollBarCommand

        self.showFilteredLines(filterTxt)

    def refreshFilter(self, filterTxt):
        if filterTxt == self.filterTxt:
            return

        self.currentOffset = 0
        self.currentSelectionIdx = 0
        self.showFilteredLines(filterTxt)

    def getCurrentSelection(self):
        return self.filteredItems[self.currentOffset + self.currentSelectionIdx]

    def moveSelection(self, command):
        for listBox in self.listBoxes:
            listBox.selection_clear(self.currentSelectionIdx)

        if command == 'Down':
            self.currentSelectionIdx += 1
        elif command == 'PageDown':
            self.currentSelectionIdx += 5
        elif command == 'Up':
            self.currentSelectionIdx -= 1
        elif command == 'PageUp':
            self.currentSelectionIdx -= 5

        if self.currentSelectionIdx >= self.numRowsShown:
            self.currentSelectionIdx = self.numRowsShown -1
            self.scrollBarCommand('scroll', 1, 'units')
        elif self.currentSelectionIdx < 0:
            self.currentSelectionIdx = 0
            self.scrollBarCommand('scroll', -1, 'units')
        else:
            self.showSelection()

    def showFilteredLines(self, filterTxt):
        if filterTxt:
            if self.filterTxt in filterTxt:
                self.filteredItems = [it for it in self.filteredItems if it.satisfies(filterTxt)]
            else:
                self.filteredItems = [it for it in self.allItems if it.satisfies(filterTxt)]
        else:
            self.filteredItems = self.allItems

        self.filterTxt = filterTxt
        self.showFilteredLinesWithCurrentOffset()

    @property
    def numFilteredItems(self):
        return len(self.filteredItems)

    def showFilteredLinesWithCurrentOffset(self):
        for listBox in self.listBoxes:
            listBox.delete(0, NUM_LINES_TO_SHOW)

        if self.numFilteredItems == 0:
            return

        self.numRowsShown = min(self.numFilteredItems, NUM_LINES_TO_SHOW)

        for (colIdx, listBox) in enumerate(self.listBoxes):
            for rowIdx in range(self.numRowsShown):
                listBox.insert(rowIdx, self.filteredItems[rowIdx + self.currentOffset].getTxt(colIdx))

        r1 = self.currentOffset / self.numFilteredItems
        r2 = (self.currentOffset  + self.numRowsShown) / self.numFilteredItems
        self.scrollBar.set(r1, r2)

        self.showSelection()

    def showSelection(self):
        for listBox in self.listBoxes:
            listBox.selection_set(self.currentSelectionIdx)

    def scrollBarCommand(self, cmd, num, units=None):
        maxLines = self.numFilteredItems
        if cmd == 'scroll':
            if units == 'units':
                self.currentOffset += 1 * int(num)
            elif units == 'pages':
                self.currentOffset += 10 * int(num)
        elif cmd == 'moveto':
            self.currentOffset = int(float(num) * maxLines)

        if self.currentOffset < 0:
            self.currentOffset = 0

        if self.currentOffset >= maxLines - NUM_LINES_TO_SHOW:
            self.currentOffset = maxLines - NUM_LINES_TO_SHOW
            if self.currentOffset < 0:
                self.currentOffset = 0

        self.showFilteredLinesWithCurrentOffset()

