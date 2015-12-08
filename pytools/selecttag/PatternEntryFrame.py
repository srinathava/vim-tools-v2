from Tkinter import *

class PatternEntryFrame(Frame):
    def __init__(self, parent):
        Frame.__init__(self, parent)

        self.label = Label(self, text="Pattern")
        self.label.pack(side=LEFT)

        self.onChange = None
        self.onKeyPress = None

        self.stringVar = StringVar()
        self.stringVar.trace('w', self.callObservers)

        self.entry = Entry(self, width=50, textvariable=self.stringVar)
        self.entry.pack(side=LEFT)

        self.entry.bind('<Down>', lambda *args: self.broadcast('Down'))
        self.entry.bind('<Control-j>', lambda *args: self.broadcast('Down'))
        self.entry.bind('<Up>', lambda *args: self.broadcast('Up'))
        self.entry.bind('<Control-k>', lambda *args: self.broadcast('Up'))
        self.entry.bind('<Next>', lambda *args: self.broadcast('PageDown'))
        self.entry.bind('<Control-f>', lambda *args: self.broadcast('PageDown'))
        self.entry.bind('<Prior>', lambda *args: self.broadcast('PageUp'))
        self.entry.bind('<Control-b>', lambda *args: self.broadcast('PageUp'))
        self.entry.bind('<Return>', lambda *args: self.broadcast('Return'))
        self.entry.bind('<Escape>', lambda *args: self.broadcast('Esc'))

    def broadcast(self, key):
        if self.onKeyPress:
            self.onKeyPress(key)

    def callObservers(self, *args):
        if self.onChange:
            self.onChange(self.stringVar.get())


