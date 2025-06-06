
/**
 * Implementation of the native Cocoa View that serves as container for the scintilla parts.
 *
 * Created by Mike Lischke.
 *
 * Copyright 2011, 2013, Oracle and/or its affiliates. All rights reserved.
 * Copyright 2009, 2011 Sun Microsystems, Inc. All rights reserved.
 * This file is dual licensed under LGPL v2.1 and the Scintilla license (http://www.scintilla.org/License.txt).
 */

#import "ScintillaView.h"

using namespace Scintilla;

// Two additional cursors we need, which aren't provided by Cocoa.
static NSCursor* reverseArrowCursor;
static NSCursor* waitCursor;

// The scintilla indicator used for keyboard input.
#define INPUT_INDICATOR INDIC_MAX - 1

NSString *SCIUpdateUINotification = @"SCIUpdateUI";

/**
 * Provide an NSCursor object that matches the Window::Cursor enumeration.
 */
static NSCursor *cursorFromEnum(Window::Cursor cursor)
{
  switch (cursor)
  {
    case Window::cursorText:
      return [NSCursor IBeamCursor];
    case Window::cursorArrow:
      return [NSCursor arrowCursor];
    case Window::cursorWait:
      return waitCursor;
    case Window::cursorHoriz:
      return [NSCursor resizeLeftRightCursor];
    case Window::cursorVert:
      return [NSCursor resizeUpDownCursor];
    case Window::cursorReverseArrow:
      return reverseArrowCursor;
    case Window::cursorUp:
    default:
      return [NSCursor arrowCursor];
  }
}


@implementation MarginView

@synthesize marginWidth, owner;

- (id)initWithScrollView:(NSScrollView *)aScrollView
{
  self = [super initWithScrollView:aScrollView orientation:NSVerticalRuler];
  if (self != nil)
  {
    owner = nil;
    marginWidth = 20;
    currentCursors = [[NSMutableArray arrayWithCapacity:0] retain];
    for (size_t i=0; i<5; i++)
    {
      [currentCursors addObject: [reverseArrowCursor retain]];
    }
    [self setClientView:[aScrollView documentView]];
  }
  return self;
}

- (void) dealloc
{
  [currentCursors release];
  [super dealloc];
}

- (void) setFrame: (NSRect) frame
{
  [super setFrame: frame];
  
  [[self window] invalidateCursorRectsForView: self];
}

- (CGFloat)requiredThickness
{
  return marginWidth;
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)aRect
{
  if (owner) {
    NSRect contentRect = [[[self scrollView] contentView] bounds];
    NSRect marginRect = [self bounds];
    // Ensure paint to bottom of view to avoid glitches
    if (marginRect.size.height > contentRect.size.height) {
      // Legacy scroll bar mode leaves a poorly painted corner
      aRect = marginRect;
    }
    owner.backend->PaintMargin(aRect);
  }
}

- (void) mouseDown: (NSEvent *) theEvent
{
  owner.backend->MouseDown(theEvent);
}

- (void) mouseDragged: (NSEvent *) theEvent
{
  owner.backend->MouseMove(theEvent);
}

- (void) mouseMoved: (NSEvent *) theEvent
{
  owner.backend->MouseMove(theEvent);
}

- (void) mouseUp: (NSEvent *) theEvent
{
  owner.backend->MouseUp(theEvent);
}

/**
 * This method is called to give us the opportunity to define our mouse sensitive rectangle.
 */
- (void) resetCursorRects
{
  [super resetCursorRects];
  
  int x = 0;
  NSRect marginRect = [self bounds];
  size_t co = [currentCursors count];
  for (size_t i=0; i<co; i++)
  {
    int cursType = owner.backend->WndProc(SCI_GETMARGINCURSORN, i, 0);
    int width =owner.backend->WndProc(SCI_GETMARGINWIDTHN, i, 0);
    NSCursor *cc = cursorFromEnum(static_cast<Window::Cursor>(cursType));
    [currentCursors replaceObjectAtIndex:i withObject: cc];
    marginRect.origin.x = x;
    marginRect.size.width = width;
    [self addCursorRect: marginRect cursor: cc];
    [cc setOnMouseEntered: YES];
    x += width;
  }
}

@end

@implementation InnerView

@synthesize owner = mOwner;

//--------------------------------------------------------------------------------------------------

- (NSView*) initWithFrame: (NSRect) frame
{
  self = [super initWithFrame: frame];
  
  if (self != nil)
  {
    // Some initialization for our view.
    mCurrentCursor = [[NSCursor arrowCursor] retain];
    mCurrentTrackingRect = 0;
    mMarkedTextRange = NSMakeRange(NSNotFound, 0);
    
    [self registerForDraggedTypes: [NSArray arrayWithObjects:
                                   NSStringPboardType, ScintillaRecPboardType, NSFilenamesPboardType, nil]];
  }
  
  return self;
}

//--------------------------------------------------------------------------------------------------

/**
 * When the view is resized we need to update our tracking rectangle and let the backend know.
 */
- (void) setFrame: (NSRect) frame
{
  [super setFrame: frame];

  // Make the content also a tracking rectangle for mouse events.
  if (mCurrentTrackingRect != 0)
    [self removeTrackingRect: mCurrentTrackingRect];
	mCurrentTrackingRect = [self addTrackingRect: [self bounds]
                                         owner: self
                                      userData: nil
                                  assumeInside: YES];
  mOwner.backend->Resize();
}

//--------------------------------------------------------------------------------------------------

/**
 * Called by the backend if a new cursor must be set for the view.
 */
- (void) setCursor: (Window::Cursor) cursor
{
  [mCurrentCursor autorelease];
  mCurrentCursor = cursorFromEnum(cursor);
  [mCurrentCursor retain];
  
  // Trigger recreation of the cursor rectangle(s).
  [[self window] invalidateCursorRectsForView: self];
}

//--------------------------------------------------------------------------------------------------

/**
 * This method is called to give us the opportunity to define our mouse sensitive rectangle.
 */
- (void) resetCursorRects
{
  [super resetCursorRects];
  
  // We only have one cursor rect: our bounds.
  [self addCursorRect: [self bounds] cursor: mCurrentCursor];
  [mCurrentCursor setOnMouseEntered: YES];
}

//--------------------------------------------------------------------------------------------------

/**
 * Gets called by the runtime when the view needs repainting.
 */
- (void) drawRect: (NSRect) rect
{
  CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
  
  if (!mOwner.backend->Draw(rect, context)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setNeedsDisplay:YES];
    });
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Windows uses a client coordinate system where the upper left corner is the origin in a window
 * (and so does Scintilla). We have to adjust for that. However by returning YES here, we are 
 * already done with that.
 * Note that because of returning YES here most coordinates we use now (e.g. for painting,
 * invalidating rectangles etc.) are given with +Y pointing down!
 */
- (BOOL) isFlipped
{
  return YES;
}

//--------------------------------------------------------------------------------------------------

- (BOOL) isOpaque
{
  return YES;
}

//--------------------------------------------------------------------------------------------------

/**
 * Implement the "click through" behavior by telling the caller we accept the first mouse event too.
 */
- (BOOL) acceptsFirstMouse: (NSEvent *) theEvent
{
#pragma unused(theEvent)
  return YES;
}

//--------------------------------------------------------------------------------------------------

/**
 * Make this view accepting events as first responder.
 */
- (BOOL) acceptsFirstResponder
{
  return YES;
}

//--------------------------------------------------------------------------------------------------

/**
 * Called by the framework if it wants to show a context menu for the editor.
 */
- (NSMenu*) menuForEvent: (NSEvent*) theEvent
{
  if (![mOwner respondsToSelector: @selector(menuForEvent:)])
    return mOwner.backend->CreateContextMenu(theEvent);
  else
    return [mOwner menuForEvent: theEvent];
}

//--------------------------------------------------------------------------------------------------

// Adoption of NSTextInput protocol.

- (NSAttributedString*) attributedSubstringFromRange: (NSRange) range
{
  return nil;
}

//--------------------------------------------------------------------------------------------------

- (NSUInteger) characterIndexForPoint: (NSPoint) point
{
  return NSNotFound;
}

//--------------------------------------------------------------------------------------------------

- (NSInteger) conversationIdentifier
{
  return (NSInteger) self;

}

//--------------------------------------------------------------------------------------------------

- (void) doCommandBySelector: (SEL) selector
{
  if ([self respondsToSelector: @selector(selector)])
    [self performSelector: selector withObject: nil];
}

//--------------------------------------------------------------------------------------------------

- (NSRect) firstRectForCharacterRange: (NSRange) range
{
  return NSZeroRect;
}

//--------------------------------------------------------------------------------------------------

- (BOOL) hasMarkedText
{
  return mMarkedTextRange.length > 0;
}

//--------------------------------------------------------------------------------------------------

/**
 * General text input. Used to insert new text at the current input position, replacing the current
 * selection if there is any.
 */
- (void) insertText: (id) aString
{
	// Remove any previously marked text first.
	[self removeMarkedText];
	NSString* newText = @"";
	if ([aString isKindOfClass:[NSString class]])
		newText = (NSString*) aString;
	else if ([aString isKindOfClass:[NSAttributedString class]])
		newText = (NSString*) [aString string];
	
	mOwner.backend->InsertText(newText);
}

//--------------------------------------------------------------------------------------------------

- (NSRange) markedRange
{
  return mMarkedTextRange;
}

//--------------------------------------------------------------------------------------------------

- (NSRange) selectedRange
{
  long begin = [mOwner getGeneralProperty: SCI_GETSELECTIONSTART parameter: 0];
  long end = [mOwner getGeneralProperty: SCI_GETSELECTIONEND parameter: 0];
  return NSMakeRange(begin, end - begin);
}

//--------------------------------------------------------------------------------------------------

/**
 * Called by the input manager to set text which might be combined with further input to form
 * the final text (e.g. composition of ^ and a to â).
 *
 * @param aString The text to insert, either what has been marked already or what is selected already
 *                or simply added at the current insertion point. Depending on what is available.
 * @param range The range of the new text to select (given relative to the insertion point of the new text).
 */
- (void) setMarkedText: (id) aString selectedRange: (NSRange) range
{
  NSString* newText = @"";
  if ([aString isKindOfClass:[NSString class]])
    newText = (NSString*) aString;
  else
    if ([aString isKindOfClass:[NSAttributedString class]])
      newText = (NSString*) [aString string];
  
  long currentPosition = [mOwner getGeneralProperty: SCI_GETCURRENTPOS parameter: 0];

  // Replace marked text if there is one.
  if (mMarkedTextRange.length > 0)
  {
    [mOwner setGeneralProperty: SCI_SETSELECTIONSTART
                         value: mMarkedTextRange.location];
    [mOwner setGeneralProperty: SCI_SETSELECTIONEND 
                         value: mMarkedTextRange.location + mMarkedTextRange.length];
    currentPosition = mMarkedTextRange.location;
  }

  // Keep Scintilla from collecting undo actions for the composition task.
  undoCollectionWasActive = [mOwner getGeneralProperty: SCI_GETUNDOCOLLECTION] != 0;
  [mOwner setGeneralProperty: SCI_SETUNDOCOLLECTION value: 0];
  
  // Note: Scintilla internally works almost always with bytes instead chars, so we need to take
  //       this into account when determining selection ranges and such.
  std::string raw_text = [newText UTF8String];
  int lengthInserted = mOwner.backend->InsertText(newText);

  mMarkedTextRange.location = currentPosition;
  mMarkedTextRange.length = lengthInserted;
    
  if (lengthInserted > 0)
  {
    // Mark the just inserted text. Keep the marked range for later reset.
    [mOwner setGeneralProperty: SCI_SETINDICATORCURRENT value: INPUT_INDICATOR];
    [mOwner setGeneralProperty: SCI_INDICATORFILLRANGE
                     parameter: mMarkedTextRange.location
                         value: mMarkedTextRange.length];
  }
  else
  {
    // Re-enable undo action collection if composition ended (indicated by an empty mark string).
    if (undoCollectionWasActive)
      [mOwner setGeneralProperty: SCI_SETUNDOCOLLECTION value: range.length == 0];
  }

  // Select the part which is indicated in the given range. It does not scroll the caret into view.
  if (range.length > 0)
  {
    [mOwner setGeneralProperty: SCI_SETSELECTIONSTART
                     value: currentPosition + range.location];
    [mOwner setGeneralProperty: SCI_SETSELECTIONEND 
                     value: currentPosition + range.location + range.length];
  }
}

//--------------------------------------------------------------------------------------------------

- (void) unmarkText
{
  if (mMarkedTextRange.length > 0)
  {
    [mOwner setGeneralProperty: SCI_SETINDICATORCURRENT value: INPUT_INDICATOR];
    [mOwner setGeneralProperty: SCI_INDICATORCLEARRANGE
                     parameter: mMarkedTextRange.location
                         value: mMarkedTextRange.length];
    mMarkedTextRange = NSMakeRange(NSNotFound, 0);

    // Reenable undo action collection, after we are done with text composition.    
    if (undoCollectionWasActive)
      [mOwner setGeneralProperty: SCI_SETUNDOCOLLECTION value: 1];
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Removes any currently marked text.
 */
- (void) removeMarkedText
{
  if (mMarkedTextRange.length > 0)
  {
    // We have already marked text. Replace that.
    [mOwner setGeneralProperty: SCI_SETSELECTIONSTART
                     value: mMarkedTextRange.location];
    [mOwner setGeneralProperty: SCI_SETSELECTIONEND 
                     value: mMarkedTextRange.location + mMarkedTextRange.length];
    mOwner.backend->InsertText(@"");
    mMarkedTextRange = NSMakeRange(NSNotFound, 0);

    // Reenable undo action collection, after we are done with text composition.    
    if (undoCollectionWasActive)
      [mOwner setGeneralProperty: SCI_SETUNDOCOLLECTION value: 1];
  }
}

//--------------------------------------------------------------------------------------------------

- (NSArray*) validAttributesForMarkedText
{
  return nil;
}

// End of the NSTextInput protocol adoption.

//--------------------------------------------------------------------------------------------------

/**
 * Generic input method. It is used to pass on keyboard input to Scintilla. The control itself only
 * handles shortcuts. The input is then forwarded to the Cocoa text input system, which in turn does
 * its own input handling (character composition via NSTextInput protocol):
 */
- (void) keyDown: (NSEvent *) theEvent
{
  if (mMarkedTextRange.length == 0)
	mOwner.backend->KeyboardInput(theEvent);
  NSArray* events = [NSArray arrayWithObject: theEvent];
  [self interpretKeyEvents: events];
}

//--------------------------------------------------------------------------------------------------

- (void) mouseDown: (NSEvent *) theEvent  
{
  mOwner.backend->MouseDown(theEvent);
}

//--------------------------------------------------------------------------------------------------

- (void) mouseDragged: (NSEvent *) theEvent
{
  mOwner.backend->MouseMove(theEvent);
}

//--------------------------------------------------------------------------------------------------

- (void) mouseUp: (NSEvent *) theEvent
{
  mOwner.backend->MouseUp(theEvent);
}

//--------------------------------------------------------------------------------------------------

- (void) mouseMoved: (NSEvent *) theEvent
{
  mOwner.backend->MouseMove(theEvent);
}

//--------------------------------------------------------------------------------------------------

- (void) mouseEntered: (NSEvent *) theEvent
{
  mOwner.backend->MouseEntered(theEvent);
}

//--------------------------------------------------------------------------------------------------

- (void) mouseExited: (NSEvent *) theEvent
{
  mOwner.backend->MouseExited(theEvent);
}

//--------------------------------------------------------------------------------------------------

/**
 * Mouse wheel with command key magnifies text.
 */
- (void) scrollWheel: (NSEvent *) theEvent
{
  if (([theEvent modifierFlags] & NSCommandKeyMask) != 0) {
    mOwner.backend->MouseWheel(theEvent);
  } else {
    [super scrollWheel:theEvent];
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Ensure scrolling is aligned to whole lines instead of starting part-way through a line
 */
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
  NSRect rc = proposedVisibleRect;
  // Snap to lines
  NSRect contentRect = [self bounds];
  if ((rc.origin.y > 0) && (NSMaxY(rc) < contentRect.size.height)) {
    // Only snap for positions inside the document - allow outside
    // for overshoot.
    int lineHeight = mOwner.backend->WndProc(SCI_TEXTHEIGHT, 0, 0);
    rc.origin.y = roundf(rc.origin.y / lineHeight) * lineHeight;
  }
  return rc;
}

//--------------------------------------------------------------------------------------------------

/**
 * The editor is getting the foreground control (the one getting the input focus).
 */
- (BOOL) becomeFirstResponder
{
  mOwner.backend->WndProc(SCI_SETFOCUS, 1, 0);
  return YES;
}

//--------------------------------------------------------------------------------------------------

/**
 * The editor is losing the input focus.
 */
- (BOOL) resignFirstResponder
{
  mOwner.backend->WndProc(SCI_SETFOCUS, 0, 0);
  return YES;
}

//--------------------------------------------------------------------------------------------------

/**
 * Called when an external drag operation enters the view. 
 */
- (NSDragOperation) draggingEntered: (id <NSDraggingInfo>) sender
{
  return mOwner.backend->DraggingEntered(sender);
}

//--------------------------------------------------------------------------------------------------

/**
 * Called frequently during an external drag operation if we are the target.
 */
- (NSDragOperation) draggingUpdated: (id <NSDraggingInfo>) sender
{
  return mOwner.backend->DraggingUpdated(sender);
}

//--------------------------------------------------------------------------------------------------

/**
 * Drag image left the view. Clean up if necessary.
 */
- (void) draggingExited: (id <NSDraggingInfo>) sender
{
  mOwner.backend->DraggingExited(sender);
}

//--------------------------------------------------------------------------------------------------

- (BOOL) prepareForDragOperation: (id <NSDraggingInfo>) sender
{
#pragma unused(sender)
  return YES;
}

//--------------------------------------------------------------------------------------------------

- (BOOL) performDragOperation: (id <NSDraggingInfo>) sender
{
  return mOwner.backend->PerformDragOperation(sender);  
}

//--------------------------------------------------------------------------------------------------

/**
 * Returns operations we allow as drag source.
 */
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) flag
{
  return NSDragOperationCopy | NSDragOperationMove | NSDragOperationDelete;
}

//--------------------------------------------------------------------------------------------------

/**
 * Finished a drag: may need to delete selection.
 */

- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    if (operation == NSDragOperationDelete) {
        mOwner.backend->WndProc(SCI_CLEAR, 0, 0);
    }
}

//--------------------------------------------------------------------------------------------------

/**
 * Drag operation is done. Notify editor.
 */
- (void) concludeDragOperation: (id <NSDraggingInfo>) sender
{
  // Clean up is the same as if we are no longer the drag target.
  mOwner.backend->DraggingExited(sender);
}

//--------------------------------------------------------------------------------------------------

// NSResponder actions.

- (void) selectAll: (id) sender
{
#pragma unused(sender)
  mOwner.backend->SelectAll();
}

- (void) deleteBackward: (id) sender
{
#pragma unused(sender)
  mOwner.backend->DeleteBackward();
}

- (void) cut: (id) sender
{
#pragma unused(sender)
  mOwner.backend->Cut();
}

- (void) copy: (id) sender
{
#pragma unused(sender)
  mOwner.backend->Copy();
}

- (void) paste: (id) sender
{
#pragma unused(sender)
  mOwner.backend->Paste();
}

- (void) undo: (id) sender
{
#pragma unused(sender)
  mOwner.backend->Undo();
}

- (void) redo: (id) sender
{
#pragma unused(sender)
  mOwner.backend->Redo();
}

- (BOOL) canUndo
{
  return mOwner.backend->CanUndo();
}

- (BOOL) canRedo
{
  return mOwner.backend->CanRedo();
}


- (BOOL) isEditable
{
  return mOwner.backend->WndProc(SCI_GETREADONLY, 0, 0) == 0;
}

//--------------------------------------------------------------------------------------------------

- (void) dealloc
{
  [mCurrentCursor release];
  [super dealloc];
}

@end

//--------------------------------------------------------------------------------------------------

@implementation ScintillaView

@synthesize backend = mBackend;
@synthesize delegate = mDelegate;
@synthesize scrollView;

/**
 * ScintillaView is a composite control made from an NSView and an embedded NSView that is
 * used as canvas for the output (by the backend, using its CGContext), plus other elements
 * (scrollers, info bar).
 */

//--------------------------------------------------------------------------------------------------

/**
 * Initialize custom cursor.
 */
+ (void) initialize
{
  if (self == [ScintillaView class])
  {
    NSBundle* bundle = [NSBundle bundleForClass: [ScintillaView class]];
    
    NSString* path = [bundle pathForResource: @"mac_cursor_busy" ofType: @"png" inDirectory: nil];
    NSImage* image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
    waitCursor = [[NSCursor alloc] initWithImage: image hotSpot: NSMakePoint(2, 2)];
    
    path = [bundle pathForResource: @"mac_cursor_flipped" ofType: @"png" inDirectory: nil];
    image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
    reverseArrowCursor = [[NSCursor alloc] initWithImage: image hotSpot: NSMakePoint(12, 2)];
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Receives zoom messages, for example when a "pinch zoom" is performed on the trackpad.
 */
- (void) magnifyWithEvent: (NSEvent *) event
{
#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
  zoomDelta += event.magnification * 10.0;

  if (fabsf(zoomDelta)>=1.0) {
    long zoomFactor = [self getGeneralProperty: SCI_GETZOOM] + zoomDelta;
    [self setGeneralProperty: SCI_SETZOOM parameter: zoomFactor value:0];
    zoomDelta = 0.0;
  }     
#endif
}

- (void) beginGestureWithEvent: (NSEvent *) event
{
  zoomDelta = 0.0;
}

//--------------------------------------------------------------------------------------------------

/**
 * Sends a new notification of the given type to the default notification center.
 */
- (void) sendNotification: (NSString*) notificationName
{
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center postNotificationName: notificationName object: self];
}

//--------------------------------------------------------------------------------------------------

/**
 * Called by a connected component (usually the info bar) if something changed there.
 *
 * @param type The type of the notification.
 * @param message Carries the new status message if the type is a status message change.
 * @param location Carries the new location (e.g. caret) if the type is a caret change or similar type.
 * @param location Carries the new zoom value if the type is a zoom change.
 */
- (void) notify: (NotificationType) type message: (NSString*) message location: (NSPoint) location
          value: (float) value
{
  switch (type)
  {
    case IBNZoomChanged:
    {
      // Compute point increase/decrease based on default font size.
      long fontSize = [self getGeneralProperty: SCI_STYLEGETSIZE parameter: STYLE_DEFAULT];
      int zoom = (int) (fontSize * (value - 1));
      [self setGeneralProperty: SCI_SETZOOM value: zoom];
      break;
    }
    default:
      break;
  };
}

//--------------------------------------------------------------------------------------------------

- (void) setCallback: (id <InfoBarCommunicator>) callback
{
  // Not used. Only here to satisfy protocol.
}

//--------------------------------------------------------------------------------------------------

/**
 * Prevents drawing of the inner view to avoid flickering when doing many visual updates
 * (like clearing all marks and setting new ones etc.).
 */
- (void) suspendDrawing: (BOOL) suspend
{
  if (suspend)
    [[self window] disableFlushWindow];
  else
    [[self window] enableFlushWindow];
}

//--------------------------------------------------------------------------------------------------

/**
 * Notification function used by Scintilla to call us back (e.g. for handling clicks on the 
 * folder margin or changes in the editor).
 * A delegate can be set to receive all notifications. If set no handling takes place here, except
 * for action pertaining to internal stuff (like the info bar).
 */
static void notification(intptr_t windowid, unsigned int iMessage, uintptr_t wParam, uintptr_t lParam)
{
  // WM_NOTIFY means we got a parent notification with a special notification structure.
  // Here we don't really differentiate between parent and own notifications and handle both.
  ScintillaView* editor;
  switch (iMessage)
  {
    case WM_NOTIFY:
    {
      // Parent notification. Details are passed as SCNotification structure.
      SCNotification* scn = reinterpret_cast<SCNotification*>(lParam);
      ScintillaCocoa *psc = reinterpret_cast<ScintillaCocoa*>(scn->nmhdr.hwndFrom);
      editor = reinterpret_cast<InnerView*>(psc->ContentView()).owner;

      if (editor.delegate != nil)
      {
        [editor.delegate notification: scn];
        if (scn->nmhdr.code != SCN_ZOOM && scn->nmhdr.code != SCN_UPDATEUI)
          return;
      }
      
      switch (scn->nmhdr.code)
      {
        case SCN_MARGINCLICK:
        {
          if (scn->margin == 2)
          {
            // Click on the folder margin. Toggle the current line if possible.
            long line = [editor getGeneralProperty: SCI_LINEFROMPOSITION parameter: scn->position];
            [editor setGeneralProperty: SCI_TOGGLEFOLD value: line];
          }
          break;
          };
        case SCN_MODIFIED:
        {
          // Decide depending on the modification type what to do.
          // There can be more than one modification carried by one notification.
          if (scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT))
            [editor sendNotification: NSTextDidChangeNotification];
          break;
        }
        case SCN_ZOOM:
        {
          // A zoom change happend. Notify info bar if there is one.
          float zoom = [editor getGeneralProperty: SCI_GETZOOM parameter: 0];
          long fontSize = [editor getGeneralProperty: SCI_STYLEGETSIZE parameter: STYLE_DEFAULT];
          float factor = (zoom / fontSize) + 1;
          [editor->mInfoBar notify: IBNZoomChanged message: nil location: NSZeroPoint value: factor];
          break;
        }
        case SCN_UPDATEUI:
        {
          // Triggered whenever changes in the UI state need to be reflected.
          // These can be: caret changes, selection changes etc.
          NSPoint caretPosition = editor->mBackend->GetCaretPosition();
          [editor->mInfoBar notify: IBNCaretChanged message: nil location: caretPosition value: 0];
          [editor sendNotification: SCIUpdateUINotification];
          [editor sendNotification: NSTextViewDidChangeSelectionNotification];
          break;
      }
      }
      break;
    }
    case WM_COMMAND:
    {
      // Notifications for the editor itself.
      ScintillaCocoa* backend = reinterpret_cast<ScintillaCocoa*>(lParam);
      editor = backend->TopContainer();
      switch (wParam >> 16)
      {
        case SCEN_KILLFOCUS:
          [editor sendNotification: NSTextDidEndEditingNotification];
          break;
        case SCEN_SETFOCUS: // Nothing to do for now.
          break;
      }
      break;
    }
  };
}

//--------------------------------------------------------------------------------------------------

/**
 * Initialization of the view. Used to setup a few other things we need.
 */
- (id) initWithFrame: (NSRect) frame
{
  self = [super initWithFrame:frame];
  if (self)
  {
    mContent = [[[InnerView alloc] init] autorelease];
    mContent.owner = self;

    // Initialize the scrollers but don't show them yet.
    // Pick an arbitrary size, just to make NSScroller selecting the proper scroller direction
    // (horizontal or vertical).
    NSRect scrollerRect = NSMakeRect(0, 0, 100, 10);
    scrollView = [[[NSScrollView alloc] initWithFrame: scrollerRect] autorelease];
    [scrollView setDocumentView: mContent];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:YES];
    [scrollView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
    //[scrollView setScrollerStyle:NSScrollerStyleLegacy];
    //[scrollView setScrollerKnobStyle:NSScrollerKnobStyleDark];
    //[scrollView setHorizontalScrollElasticity:NSScrollElasticityNone];
    [self addSubview: scrollView];

    marginView = [[MarginView alloc] initWithScrollView:scrollView];
    marginView.owner = self;
    [marginView setRuleThickness:[marginView requiredThickness]];
    [scrollView setVerticalRulerView:marginView];
    [scrollView setHasHorizontalRuler:NO];
    [scrollView setHasVerticalRuler:YES];
    [scrollView setRulersVisible:YES];
    
    mBackend = new ScintillaCocoa(mContent, marginView);

    // Establish a connection from the back end to this container so we can handle situations
    // which require our attention.
    mBackend->RegisterNotifyCallback(nil, notification);
    
    // Setup a special indicator used in the editor to provide visual feedback for 
    // input composition, depending on language, keyboard etc.
    [self setColorProperty: SCI_INDICSETFORE parameter: INPUT_INDICATOR fromHTML: @"#FF0000"];
    [self setGeneralProperty: SCI_INDICSETUNDER parameter: INPUT_INDICATOR value: 1];
    [self setGeneralProperty: SCI_INDICSETSTYLE parameter: INPUT_INDICATOR value: INDIC_PLAIN];
    [self setGeneralProperty: SCI_INDICSETALPHA parameter: INPUT_INDICATOR value: 100];
      
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(applicationDidResignActive:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
      
    [center addObserver:self
               selector:@selector(applicationDidBecomeActive:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];

    [[scrollView contentView] setPostsBoundsChangedNotifications:YES];
    [center addObserver:self
	       selector:@selector(scrollerAction:)
		   name:NSViewBoundsDidChangeNotification
		 object:[scrollView contentView]];
  }
  return self;
}

//--------------------------------------------------------------------------------------------------

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  delete mBackend;
  [super dealloc];
}

//--------------------------------------------------------------------------------------------------

- (void) applicationDidResignActive: (NSNotification *)note {
#pragma unused(note)
    mBackend->ActiveStateChanged(false);
}

//--------------------------------------------------------------------------------------------------

- (void) applicationDidBecomeActive: (NSNotification *)note {
#pragma unused(note)
    mBackend->ActiveStateChanged(true);
}

//--------------------------------------------------------------------------------------------------

- (void) viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  
  [self positionSubViews];
  
  // Enable also mouse move events for our window (and so this view).
  [[self window] setAcceptsMouseMovedEvents: YES];
}

//--------------------------------------------------------------------------------------------------

/**
 * Used to position and size the parts of the editor (content, scrollers, info bar).
 */
- (void) positionSubViews
{
  int scrollerWidth = [NSScroller scrollerWidth];

  NSSize size = [self frame].size;
  NSRect barFrame = {0, size.height - scrollerWidth, size.width, static_cast<CGFloat>(scrollerWidth)};
  BOOL infoBarVisible = mInfoBar != nil && ![mInfoBar isHidden];

  // Horizontal offset of the content. Almost always 0 unless the vertical scroller
  // is on the left side.
  int contentX = 0;
  NSRect scrollRect = {contentX, 0, size.width, size.height};

  // Info bar frame.
  if (infoBarVisible)
  {
    scrollRect.size.height -= scrollerWidth;
    // Initial value already is as if the bar is at top.
    if (!mInfoBarAtTop)
    {
      scrollRect.origin.y += scrollerWidth;
      barFrame.origin.y = 0;
    }
  }

  if (!NSEqualRects([scrollView frame], scrollRect)) {
    [scrollView setFrame: scrollRect];
  }

  if (infoBarVisible)
    [mInfoBar setFrame: barFrame];
}

//--------------------------------------------------------------------------------------------------

/**
 * Set the width of the margin.
 */
- (void) setMarginWidth: (int) width
{
  if (marginView.ruleThickness != width)
  {
    marginView.marginWidth = width;
    [marginView setRuleThickness:[marginView requiredThickness]];
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Triggered by one of the scrollers when it gets manipulated by the user. Notify the backend
 * about the change.
 */
- (void) scrollerAction: (id) sender
{
  mBackend->UpdateForScroll();
}

//--------------------------------------------------------------------------------------------------

/**
 * Used to reposition our content depending on the size of the view.
 */
- (void) setFrame: (NSRect) newFrame
{
  NSRect previousFrame = [self frame];
  [super setFrame: newFrame];
  [self positionSubViews];
  if (!NSEqualRects(previousFrame, newFrame)) {
    mBackend->Resize();
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Getter for the currently selected text in raw form (no formatting information included).
 * If there is no text available an empty string is returned.
 */
- (NSString*) selectedString
{
  NSString *result = @"";
  
  char *buffer(0);
  const long length = mBackend->WndProc(SCI_GETSELTEXT, 0, 0);
  if (length > 0)
  {
    buffer = new char[length + 1];
    try
    {
      mBackend->WndProc(SCI_GETSELTEXT, length + 1, (sptr_t) buffer);
      
      result = [NSString stringWithUTF8String: buffer];
      delete[] buffer;
    }
    catch (...)
    {
      delete[] buffer;
      buffer = 0;
    }
  }
  
  return result;
}

//--------------------------------------------------------------------------------------------------

/**
 * Getter for the current text in raw form (no formatting information included).
 * If there is no text available an empty string is returned.
 */
- (NSString*) string
{
  NSString *result = @"";
  
  char *buffer(0);
  const long length = mBackend->WndProc(SCI_GETLENGTH, 0, 0);
  if (length > 0)
  {
    buffer = new char[length + 1];
    try
    {
      mBackend->WndProc(SCI_GETTEXT, length + 1, (sptr_t) buffer);
      
      result = [NSString stringWithUTF8String: buffer];
      delete[] buffer;
    }
    catch (...)
    {
      delete[] buffer;
      buffer = 0;
    }
  }
  
  return result;
}

//--------------------------------------------------------------------------------------------------

/**
 * Setter for the current text (no formatting included).
 */
- (void) setString: (NSString*) aString
{
  const char* text = [aString UTF8String];
  mBackend->WndProc(SCI_SETTEXT, 0, (long) text);
}

//--------------------------------------------------------------------------------------------------

- (void) insertString: (NSString*) aString atOffset: (int)offset
{
  const char* text = [aString UTF8String];
  mBackend->WndProc(SCI_ADDTEXT, offset, (long) text);
}

//--------------------------------------------------------------------------------------------------

- (void) setEditable: (BOOL) editable
{
  mBackend->WndProc(SCI_SETREADONLY, editable ? 0 : 1, 0);
}

//--------------------------------------------------------------------------------------------------

- (BOOL) isEditable
{
  return mBackend->WndProc(SCI_GETREADONLY, 0, 0) == 0;
}

//--------------------------------------------------------------------------------------------------

- (InnerView*) content
{
  return mContent;
}

//--------------------------------------------------------------------------------------------------

/**
 * Direct call into the backend to allow uninterpreted access to it. The values to be passed in and
 * the result heavily depend on the message that is used for the call. Refer to the Scintilla
 * documentation to learn what can be used here.
 */
+ (sptr_t) directCall: (ScintillaView*) sender message: (unsigned int) message wParam: (uptr_t) wParam
               lParam: (sptr_t) lParam
{
  return ScintillaCocoa::DirectFunction(sender->mBackend, message, wParam, lParam);
}

//--------------------------------------------------------------------------------------------------

/**
 * This is a helper method to set properties in the backend, with native parameters.
 *
 * @param property Main property like SCI_STYLESETFORE for which a value is to be set.
 * @param parameter Additional info for this property like a parameter or index.
 * @param value The actual value. It depends on the property what this parameter means.
 */
- (void) setGeneralProperty: (int) property parameter: (long) parameter value: (long) value
{
  mBackend->WndProc(property, parameter, value);
}

//--------------------------------------------------------------------------------------------------

/**
 * A simplified version for setting properties which only require one parameter.
 *
 * @param property Main property like SCI_STYLESETFORE for which a value is to be set.
 * @param value The actual value. It depends on the property what this parameter means.
 */
- (void) setGeneralProperty: (int) property value: (long) value
{
  mBackend->WndProc(property, value, 0);
}

//--------------------------------------------------------------------------------------------------

/**
 * This is a helper method to get a property in the backend, with native parameters.
 *
 * @param property Main property like SCI_STYLESETFORE for which a value is to get.
 * @param parameter Additional info for this property like a parameter or index.
 * @param extra Yet another parameter if needed.
 * @result A generic value which must be interpreted depending on the property queried.
 */
- (long) getGeneralProperty: (int) property parameter: (long) parameter extra: (long) extra
{
  return mBackend->WndProc(property, parameter, extra);
}

//--------------------------------------------------------------------------------------------------

/**
 * Convenience function to avoid unneeded extra parameter.
 */
- (long) getGeneralProperty: (int) property parameter: (long) parameter
{
  return mBackend->WndProc(property, parameter, 0);
}

//--------------------------------------------------------------------------------------------------

/**
 * Convenience function to avoid unneeded parameters.
 */
- (long) getGeneralProperty: (int) property
{
  return mBackend->WndProc(property, 0, 0);
}

//--------------------------------------------------------------------------------------------------

/**
 * Use this variant if you have to pass in a reference to something (e.g. a text range).
 */
- (long) getGeneralProperty: (int) property ref: (const void*) ref
{
  return mBackend->WndProc(property, 0, (sptr_t) ref);  
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property setter for colors.
 */
- (void) setColorProperty: (int) property parameter: (long) parameter value: (NSColor*) value
{
  if ([value colorSpaceName] != NSDeviceRGBColorSpace)
    value = [value colorUsingColorSpaceName: NSDeviceRGBColorSpace];
  long red = [value redComponent] * 255;
  long green = [value greenComponent] * 255;
  long blue = [value blueComponent] * 255;
  
  long color = (blue << 16) + (green << 8) + red;
  mBackend->WndProc(property, parameter, color);
}

//--------------------------------------------------------------------------------------------------

/**
 * Another color property setting, which allows to specify the color as string like in HTML
 * documents (i.e. with leading # and either 3 hex digits or 6).
 */
- (void) setColorProperty: (int) property parameter: (long) parameter fromHTML: (NSString*) fromHTML
{
  if ([fromHTML length] > 3 && [fromHTML characterAtIndex: 0] == '#')
  {
    bool longVersion = [fromHTML length] > 6;
    int index = 1;
    
    char value[3] = {0, 0, 0};
    value[0] = [fromHTML characterAtIndex: index++];
    if (longVersion)
      value[1] = [fromHTML characterAtIndex: index++];
    else
      value[1] = value[0];

    unsigned rawRed;
    [[NSScanner scannerWithString: [NSString stringWithUTF8String: value]] scanHexInt: &rawRed];

    value[0] = [fromHTML characterAtIndex: index++];
    if (longVersion)
      value[1] = [fromHTML characterAtIndex: index++];
    else
      value[1] = value[0];
    
    unsigned rawGreen;
    [[NSScanner scannerWithString: [NSString stringWithUTF8String: value]] scanHexInt: &rawGreen];

    value[0] = [fromHTML characterAtIndex: index++];
    if (longVersion)
      value[1] = [fromHTML characterAtIndex: index++];
    else
      value[1] = value[0];
    
    unsigned rawBlue;
    [[NSScanner scannerWithString: [NSString stringWithUTF8String: value]] scanHexInt: &rawBlue];

    long color = (rawBlue << 16) + (rawGreen << 8) + rawRed;
    mBackend->WndProc(property, parameter, color);
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property getter for colors.
 */
- (NSColor*) getColorProperty: (int) property parameter: (long) parameter
{
  long color = mBackend->WndProc(property, parameter, 0);
  float red = (color & 0xFF) / 255.0;
  float green = ((color >> 8) & 0xFF) / 255.0;
  float blue = ((color >> 16) & 0xFF) / 255.0;
  NSColor* result = [NSColor colorWithDeviceRed: red green: green blue: blue alpha: 1];
  return result;
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property setter for references (pointers, addresses).
 */
- (void) setReferenceProperty: (int) property parameter: (long) parameter value: (const void*) value
{
  mBackend->WndProc(property, parameter, (sptr_t) value);
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property getter for references (pointers, addresses).
 */
- (const void*) getReferenceProperty: (int) property parameter: (long) parameter
{
  return (const void*) mBackend->WndProc(property, parameter, 0);
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property setter for string values.
 */
- (void) setStringProperty: (int) property parameter: (long) parameter value: (NSString*) value
{
  const char* rawValue = [value UTF8String];
  mBackend->WndProc(property, parameter, (sptr_t) rawValue);
}


//--------------------------------------------------------------------------------------------------

/**
 * Specialized property getter for string values.
 */
- (NSString*) getStringProperty: (int) property parameter: (long) parameter
{
  const char* rawValue = (const char*) mBackend->WndProc(property, parameter, 0);
  return [NSString stringWithUTF8String: rawValue];
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property setter for lexer properties, which are commonly passed as strings.
 */
- (void) setLexerProperty: (NSString*) name value: (NSString*) value
{
  const char* rawName = [name UTF8String];
  const char* rawValue = [value UTF8String];
  mBackend->WndProc(SCI_SETPROPERTY, (sptr_t) rawName, (sptr_t) rawValue);
}

//--------------------------------------------------------------------------------------------------

/**
 * Specialized property getter for references (pointers, addresses).
 */
- (NSString*) getLexerProperty: (NSString*) name
{
  const char* rawName = [name UTF8String];
  const char* result = (const char*) mBackend->WndProc(SCI_SETPROPERTY, (sptr_t) rawName, 0);
  return [NSString stringWithUTF8String: result];
}

//--------------------------------------------------------------------------------------------------

/**
 * Sets the notification callback
 */
- (void) registerNotifyCallback: (intptr_t) windowid value: (Scintilla::SciNotifyFunc) callback
{
	mBackend->RegisterNotifyCallback(windowid, callback);
}


//--------------------------------------------------------------------------------------------------

/**
 * Sets the new control which is displayed as info bar at the top or bottom of the editor.
 * Set newBar to nil if you want to hide the bar again.
 * When aligned to bottom position then the info bar and the horizontal scroller share the available
 * space. The info bar will then only get the width it is currently set to less a minimal amount
 * reserved for the scroller. At the top position it gets the full width of the control.
 * The info bar's height is set to the height of the scrollbar.
 */
- (void) setInfoBar: (NSView <InfoBarCommunicator>*) newBar top: (BOOL) top
{
  if (mInfoBar != newBar)
  {
    [mInfoBar removeFromSuperview];
    
    mInfoBar = newBar;
    mInfoBarAtTop = top;
    if (mInfoBar != nil)
    {
      [self addSubview: mInfoBar];
      [mInfoBar setCallback: self];
      
      // Keep the initial width as reference for layout changes.
      mInitialInfoBarWidth = [mInfoBar frame].size.width;
    }
    
    [self positionSubViews];
  }
}

//--------------------------------------------------------------------------------------------------

/**
 * Sets the edit's info bar status message. This call only has an effect if there is an info bar.
 */
- (void) setStatusText: (NSString*) text
{
  if (mInfoBar != nil)
    [mInfoBar notify: IBNStatusChanged message: text location: NSZeroPoint value: 0];
}

//--------------------------------------------------------------------------------------------------

- (NSRange) selectedRange
{
  return [mContent selectedRange];
}

//--------------------------------------------------------------------------------------------------

- (void)insertText: (NSString*)text
{
  [mContent insertText: text];
}

//--------------------------------------------------------------------------------------------------

/**
 * For backwards compatibility.
 */
- (BOOL) findAndHighlightText: (NSString*) searchText
                    matchCase: (BOOL) matchCase
                    wholeWord: (BOOL) wholeWord
                     scrollTo: (BOOL) scrollTo
                         wrap: (BOOL) wrap
{
  return [self findAndHighlightText: searchText
                          matchCase: matchCase
                          wholeWord: wholeWord
                           scrollTo: scrollTo
                               wrap: wrap
                          backwards: NO];
}

//--------------------------------------------------------------------------------------------------

/**
 * Searches and marks the first occurance of the given text and optionally scrolls it into view.
 *
 * @result YES if something was found, NO otherwise.
 */
- (BOOL) findAndHighlightText: (NSString*) searchText
                    matchCase: (BOOL) matchCase
                    wholeWord: (BOOL) wholeWord
                     scrollTo: (BOOL) scrollTo
                         wrap: (BOOL) wrap
                    backwards: (BOOL) backwards
{
  int searchFlags= 0;
  if (matchCase)
    searchFlags |= SCFIND_MATCHCASE;
  if (wholeWord)
    searchFlags |= SCFIND_WHOLEWORD;

  int selectionStart = [self getGeneralProperty: SCI_GETSELECTIONSTART parameter: 0];
  int selectionEnd = [self getGeneralProperty: SCI_GETSELECTIONEND parameter: 0];
  
  // Sets the start point for the comming search to the begin of the current selection.
  // For forward searches we have therefore to set the selection start to the current selection end
  // for proper incremental search. This does not harm as we either get a new selection if something
  // is found or the previous selection is restored.
  if (!backwards)
    [self getGeneralProperty: SCI_SETSELECTIONSTART parameter: selectionEnd];
  [self setGeneralProperty: SCI_SEARCHANCHOR value: 0];
  sptr_t result;
  const char* textToSearch = [searchText UTF8String];

  // The following call will also set the selection if something was found.
  if (backwards)
  {
    result = [ScintillaView directCall: self
                               message: SCI_SEARCHPREV
                                wParam: searchFlags
                                lParam: (sptr_t) textToSearch];
    if (result < 0 && wrap)
    {
      // Try again from the end of the document if nothing could be found so far and
      // wrapped search is set.
      [self getGeneralProperty: SCI_SETSELECTIONSTART parameter: [self getGeneralProperty: SCI_GETTEXTLENGTH parameter: 0]];
      [self setGeneralProperty: SCI_SEARCHANCHOR value: 0];
      result = [ScintillaView directCall: self
                                 message: SCI_SEARCHNEXT
                                  wParam: searchFlags
                                  lParam: (sptr_t) textToSearch];
    }
  }
  else
  {
    result = [ScintillaView directCall: self
                               message: SCI_SEARCHNEXT
                                wParam: searchFlags
                                lParam: (sptr_t) textToSearch];
    if (result < 0 && wrap)
    {
      // Try again from the start of the document if nothing could be found so far and
      // wrapped search is set.
      [self getGeneralProperty: SCI_SETSELECTIONSTART parameter: 0];
      [self setGeneralProperty: SCI_SEARCHANCHOR value: 0];
      result = [ScintillaView directCall: self
                                 message: SCI_SEARCHNEXT
                                  wParam: searchFlags
                                  lParam: (sptr_t) textToSearch];
    }
  }

  if (result >= 0)
  {
    if (scrollTo)
      [self setGeneralProperty: SCI_SCROLLCARET value: 0];
  }
  else
  {
    // Restore the former selection if we did not find anything.
    [self setGeneralProperty: SCI_SETSELECTIONSTART value: selectionStart];
    [self setGeneralProperty: SCI_SETSELECTIONEND value: selectionEnd];
  }
  return (result >= 0) ? YES : NO;
}

//--------------------------------------------------------------------------------------------------

/**
 * Searches the given text and replaces
 *
 * @result Number of entries replaced, 0 if none.
 */
- (int) findAndReplaceText: (NSString*) searchText
                    byText: (NSString*) newText
                 matchCase: (BOOL) matchCase
                 wholeWord: (BOOL) wholeWord
                     doAll: (BOOL) doAll
{
  // The current position is where we start searching for single occurences. Otherwise we start at
  // the beginning of the document.
  int startPosition;
  if (doAll)
    startPosition = 0; // Start at the beginning of the text if we replace all occurrences.
  else
    // For a signle replacement we start at the current caret position.
    startPosition = [self getGeneralProperty: SCI_GETCURRENTPOS];
  int endPosition = [self getGeneralProperty: SCI_GETTEXTLENGTH];

  int searchFlags= 0;
  if (matchCase)
    searchFlags |= SCFIND_MATCHCASE;
  if (wholeWord)
    searchFlags |= SCFIND_WHOLEWORD;
  [self setGeneralProperty: SCI_SETSEARCHFLAGS value: searchFlags];
  [self setGeneralProperty: SCI_SETTARGETSTART value: startPosition];
  [self setGeneralProperty: SCI_SETTARGETEND value: endPosition];

  const char* textToSearch = [searchText UTF8String];
  int sourceLength = strlen(textToSearch); // Length in bytes.
  const char* replacement = [newText UTF8String];
  int targetLength = strlen(replacement);  // Length in bytes.
  sptr_t result;
  
  int replaceCount = 0;
  if (doAll)
  {
    while (true)
    {
      result = [ScintillaView directCall: self
                                 message: SCI_SEARCHINTARGET
                                  wParam: sourceLength
                                  lParam: (sptr_t) textToSearch];
      if (result < 0)
        break;

      replaceCount++;
      [ScintillaView directCall: self
                                 message: SCI_REPLACETARGET
                                  wParam: targetLength
                                  lParam: (sptr_t) replacement];

      // The replacement changes the target range to the replaced text. Continue after that til the end.
      // The text length might be changed by the replacement so make sure the target end is the actual
      // text end.
      [self setGeneralProperty: SCI_SETTARGETSTART value: [self getGeneralProperty: SCI_GETTARGETEND]];
      [self setGeneralProperty: SCI_SETTARGETEND value: [self getGeneralProperty: SCI_GETTEXTLENGTH]];
    }
  }
  else
  {
    result = [ScintillaView directCall: self
                               message: SCI_SEARCHINTARGET
                                wParam: sourceLength
                                lParam: (sptr_t) textToSearch];
    replaceCount = (result < 0) ? 0 : 1;

    if (replaceCount > 0)
    {
      [ScintillaView directCall: self
                                 message: SCI_REPLACETARGET
                                  wParam: targetLength
                                  lParam: (sptr_t) replacement];

    // For a single replace we set the new selection to the replaced text.
    [self setGeneralProperty: SCI_SETSELECTIONSTART value: [self getGeneralProperty: SCI_GETTARGETSTART]];
    [self setGeneralProperty: SCI_SETSELECTIONEND value: [self getGeneralProperty: SCI_GETTARGETEND]];
    }
  }
  
  return replaceCount;
}

//--------------------------------------------------------------------------------------------------

- (void) setFontName: (NSString*) font
                size: (int) size
                bold: (BOOL) bold
                italic: (BOOL) italic
{
  for (int i = 0; i < 128; i++)
  {
    [self setGeneralProperty: SCI_STYLESETFONT
                   parameter: i
                       value: (sptr_t)[font UTF8String]];
    [self setGeneralProperty: SCI_STYLESETSIZE
                   parameter: i
                       value: size];
    [self setGeneralProperty: SCI_STYLESETBOLD
                   parameter: i
                       value: bold];
    [self setGeneralProperty: SCI_STYLESETITALIC
                   parameter: i
                       value: italic];
  }
}

//--------------------------------------------------------------------------------------------------

@end

