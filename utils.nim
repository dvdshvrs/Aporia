#
#
#            Aporia - Nimrod IDE
#        (c) Copyright 2011 Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import gtk2, gtksourceview, glib2, osproc, streams, AboutDialog, asyncio, strutils
import tables

from CustomStatusBar import PCustomStatusBar

type
  TSettings* = object
    search*: TSearchEnum # Search mode.
    wrapAround*: bool # Whether to wrap the search around.
    
    font*: string # font used by the sourceview
    outputFont*: string # font used by the output textview
    colorSchemeID*: string # color scheme used by the sourceview
    indentWidth*: int32 # how many spaces used for indenting code (in sourceview)
    showLineNumbers*: bool # whether to show line numbers in the sourceview
    highlightMatchingBrackets*: bool # whether to highlight matching brackets
    rightMargin*: bool # Whether to show the right margin
    highlightCurrentLine*: bool # Whether to highlight the current line
    autoIndent*: bool

    winMaximized*: bool # Whether the MainWindow is maximized on startup
    VPanedPos*: int32 # Position of the VPaned, which splits
                      # the sourceViewTabs and bottomPanelTabs
    winWidth*, winHeight*: int32 # The size of the window.
    
    toolBarVisible*: bool # Whether the top panel is shown
    bottomPanelVisible*: bool # Whether the bottom panel is shown
    suggestFeature*: bool # Whether the suggest feature is enabled
    
    nimrodCmd*: string  # command template to use to exec the Nimrod compiler
    customCmd1*: string # command template to use to exec a custom command
    customCmd2*: string # command template to use to exec a custom command
    customCmd3*: string # command template to use to exec a custom command
    
    recentlyOpenedFiles*: seq[string] # paths of recently opened files
    singleInstancePort*: int32 # Port used for listening socket to get filepaths
    showCloseOnAllTabs*: bool # Whether to show a close btn on all tabs.
    
    
  MainWin* = object
    # Widgets
    w*: gtk2.PWindow
    suggest*: TSuggestDialog
    nimLang*: PSourceLanguage
    scheme*: PSourceStyleScheme # color scheme the sourceview is meant to use
    SourceViewTabs*: PNotebook # Tabs which hold the sourceView
    statusBar*: PCustomStatusBar
    
    infobar*: PInfoBar ## For encoding selection
    
    toolBar*: PToolBar # FIXME: should be notebook?
    bottomPanelTabs*: PNotebook
    outputTextView*: PTextView
    errorListWidget*: PTreeView
    
    findBar*: PHBox # findBar
    findEntry*: PEntry
    replaceEntry*: PEntry
    replaceLabel*: PLabel
    replaceBtn*: PButton
    replaceAllBtn*: PButton
    
    goLineBar*: TGoLineBar
    
    FileMenu*: PMenu
    
    viewToolBarMenuItem*: PMenuItem # view menu
    viewBottomPanelMenuItem*: PMenuItem # view menu

    Tabs*: seq[Tab] # Other
    
    tempStuff*: Temp # Just things to remember. TODO: Rename to `other' ?
    
    settings*: TSettings
    oneInstSock*: PAsyncSocket
    IODispatcher*: PDispatcher

  TSuggestDialog* = object
    dialog*: gtk2.PWindow
    treeView*: PTreeView
    items*: seq[TSuggestItem] ## Visible items (In the treeview)
    allItems*: seq[TSuggestItem] ## All items found in current context.
    shown*: bool
    gotAll*: bool # Whether all suggest items have been read.
    currentFilter*: string
    tooltip*: PWindow
    tooltipLabel*: PLabel
  
  TExecMode* = enum
    ExecNimrod, ExecRun, ExecCustom
  
  PExecOptions* = ref TExecOptions
  TExecOptions* = object
    command*: string
    mode*: TExecMode
    output*: bool
    onLine*: proc (win: var MainWin, opts: PExecOptions, line: string) {.closure.}
    onExit*: proc (win: var MainWin, opts: PExecOptions, exitcode: int) {.closure.}
    runAfterSuccess*: bool # If true, ``runAfter`` will only be ran on success.
    runAfter*: PExecOptions
  
  TExecThrTaskType* = enum
    ThrRun, ThrStop
  TExecThrTask* = object
    case typ*: TExecThrTaskType
    of ThrRun:
      command*: string
    of ThrStop: nil
  
  TExecThrEventType* = enum
    EvStarted, EvRecv, EvStopped
  TExecThrEvent* = object
    case typ*: TExecThrEventType
    of EvStarted:
      p*: PProcess
    of EvRecv:
      line*: string
    of EvStopped:
      exitCode*: int
  
  Temp = object
    lastSaveDir*: string # Last saved directory/last active directory
    stopSBUpdates*: Bool
    
    currentExec*: PExecOptions # nil if nothing is being executed.
    compileSuccess*: bool
    execThread*: TThread[void]
    execProcess*: PProcess
    idleFuncId*: int32
    lastProgressPulse*: float
    errorMsgStarted*: bool
    compilationErrorBuffer*: string # holds error msg if it spans multiple lines.
    errorList*: seq[TError]
    gotDefinition*: bool

    recentFileMenuItems*: seq[PMenuItem] # Menu items to be destroyed.
    lastTab*: int # For reordering tabs, the last tab that was selected.
    commentSyntax*: tuple[line: string, blockStart: string, blockEnd: string]
    pendingFilename*: string # Filename which could not be opened due to encoding.
    plMenuItems*: tables.TTable[string, tuple[mi: PCheckMenuItem, lang: PSourceLanguage]]
    stopPLToggle*: bool
    currentToggledLang*: string # ID of the currently active pl

  Tab* = object
    buffer*: PSourceBuffer
    sourceView*: PSourceView
    label*: PLabel
    closeBtn*: PButton # This is so that the close btn is only shown on selected tabs.
    saved*: bool
    filename*: string
    
  TSuggestItem* = object
    nodeType*, name*, nimType*, file*, nmName*: string
    line*, col*: int32
  
  TSearchEnum* = enum
    SearchCaseSens, SearchCaseInsens, SearchStyleInsens, SearchRegex, SearchPeg

  TGoLineBar* = object
    bar*: PHBox
    entry*: PEntry

  TErrorType* = enum
    TETError, TETWarning

  TError* = object
    kind*: TErrorType
    desc*, file*, line*, column*: string

  TEncodingsAvailable* = enum
    UTF8 = "UTF-8", ISO88591 = "ISO-8859-1", GB2312 = "GB2312",
    Windows1251 = "Windows-1251"


# -- Debug
proc echod*(s: varargs[string, `$`]) =
  when not defined(release):
    for i in items(s): stdout.write(i)
    echo()


# -- Useful TextView functions.

proc createColor*(textView: PTextView, name, color: string): PTextTag =
  # This function makes sure that the color is created only once.
  var tagTable = textView.getBuffer().getTagTable()
  result = tagTable.tableLookup(name)
  if result == nil:
    result = textView.getBuffer().createTag(name, "foreground", color, nil)

proc addText*(textView: PTextView, text: string,
             colorTag: PTextTag = nil, scroll: bool = true) =
  if text != nil:
    var iter: TTextIter
    textView.getBuffer().getEndIter(addr(iter))

    if colorTag == nil:
      textView.getBuffer().insert(addr(iter), text, int32(len(text)))
    else:
      textView.getBuffer().insertWithTags(addr(iter), text, len(text).int32, colorTag,
                                          nil)
    if scroll:
      var endMark = textView.getBuffer().getMark("endMark")
      # Yay! With the use of marks; scrolling always occurs!
      textView.scrollToMark(endMark, 0.0, False, 0.0, 1.0)

proc scrollToInsert*(win: var MainWin, tabIndex: int32 = -1) =
  var current = -1
  if tabIndex != -1: current = tabIndex
  else: current = win.SourceViewTabs.getCurrentPage()

  var mark = win.Tabs[current].buffer.getInsert()
  win.Tabs[current].sourceView.scrollToMark(mark, 0.25, False, 0.0, 0.0)

proc findTab*(win: var MainWin, filename: string, absolute: bool = true): int =
  for i in 0..win.Tabs.len()-1:
    if absolute:
      if win.Tabs[i].filename == filename: 
        return i
    else:
      if filename in win.Tabs[i].filename:
        return i 
      elif win.tabs[i].filename == "" and filename == ("a" & $i & ".nim"):
        return i

  return -1

# -- TreeIter functions
proc moveToEndLine*(iter: PTextIter) =
  ## Moves ``iter`` to the end of the current line.
  ## This guarantees that the iter will stay on the same line.
  ## Unlike gtk2's ``forwardToLineEnd``
  var currentLine = iter.getLine()
  iter.setLineOffset(0)
  discard iter.forwardToLineEnd()
  if currentLine != iter.getLine():
    # This will only happen if iter is on an empty line. We can safely return
    # to its first char, because there is no more chars on that line.
    iter.setLine(currentLine)

# -- Useful TreeView function
proc createTextColumn*(tv: PTreeView, title: string, column: int,
                      expand = false, resizable = true) =
  ## Creates a new Text column.
  var c = TreeViewColumnNew()
  var renderer = cellRendererTextNew()
  c.columnSetTitle(title)
  c.columnPackStart(renderer, expand)
  c.columnSetExpand(expand)
  c.columnSetResizable(resizable)
  c.columnSetAttributes(renderer, "text", column, nil)
  doAssert tv.appendColumn(c) == column+1

# -- Useful ListStore functions
proc add*(ls: PListStore, val: String, col = 0) =
  var iter: TTreeIter
  ls.append(addr(iter))
  ls.set(addr(iter), col, val, -1)

# -- Useful Menu functions
proc createAccelMenuItem*(toolsMenu: PMenu, accGroup: PAccelGroup, 
                         label: string, acc: gint,
                         action: proc (i: PMenuItem, p: pointer) {.cdecl.},
                         mask: gint = 0,
                         stockid: string = "") = 
  var result: PMenuItem
  if stockid != "":
    result = imageMenuItemNewFromStock(stockid, nil)
  else:
    result = menu_item_new(label)
  
  result.addAccelerator("activate", accGroup, acc, mask, ACCEL_VISIBLE)
  ToolsMenu.append(result)
  show(result)
  discard signal_connect(result, "activate", SIGNAL_FUNC(action), nil)

proc createMenuItem*(menu: PMenu, label: string, 
                     action: proc (i: PMenuItem, p: pointer) {.cdecl.}) =
  var result = menuItemNew(label)
  menu.append(result)
  show(result)
  discard signalConnect(result, "activate", SIGNALFUNC(action), nil)

proc createImageMenuItem*(menu: PMenu, stockid: string,
                          action: proc (i: PMenuItem, p: pointer) {.cdecl.}) =
  var result = imageMenuItemNewFromStock(stockid, nil)
  menu.append(result)
  show(result)
  discard signalConnect(result, "activate", SIGNALFUNC(action), nil)

proc createSeparator*(menu: PMenu) =
  var sep = separator_menu_item_new()
  menu.append(sep)
  sep.show()

# -- Others

proc getCurrentTab*(win: var MainWin): int =
  result = win.sourceViewTabs.GetCurrentPage()
  if result < 0:
    result = 0

proc getCurrentLanguage*(win: var MainWin, pageNum: int = -1): string =
  ## Returns the current language ID.
  ##
  ## ``""`` is returned if there is no syntax highlighting for the current doc.
  var currentPage = pageNum
  if currentPage == -1:
    currentPage = win.getCurrentTab()
  var isHighlighted = win.Tabs[currentPage].buffer.getHighlightSyntax()
  if isHighlighted:
    var SourceLanguage = win.Tabs[currentPage].buffer.getLanguage()
    if SourceLanguage == nil: return ""
    return $sourceLanguage.getID()
  else:
    return ""

proc getCurrentLanguageComment*(win: var MainWin,
          syntax: var tuple[line, blockStart, blockEnd: string], pageNum: int) =
  ## Gets the current line comment string and block comment string.
  ## If no comment can be found ``false`` is returned.
  
  var currentLang = getCurrentLanguage(win, pageNum)
  if currentLang != "":
    case currentLang.normalize()
    of "nimrod":
      syntax.blockStart = "discard \"\"\""
      syntax.blockEnd = "\"\"\""
      syntax.line = "#"
    else:
      var SourceLanguage = win.Tabs[pageNum].buffer.getLanguage()
      var bs = sourceLanguage.getMetadata("block-comment-start")
      var be = sourceLanguage.getMetadata("block-comment-end")
      var lc = sourceLanguage.getMetadata("line-comment-start")
      syntax.blockStart  = if bs != nil: $bs else: ""
      syntax.blockEnd    = if be != nil: $be else: ""
      syntax.line = if lc != nil: $lc else: ""
  else:
    syntax.blockStart = ""
    syntax.blockEnd = ""
    syntax.line = ""
