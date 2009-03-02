/*
 * Author: patrick@collison.ie
 * Records mouse movements, clicks, frontmost app, and key presses (NOT the key code itself, just that a key was pressed)
 * Usage:
 * gcc -framework Foundation -framework Cocoa noprocrast.m -o noprocrast
 * ./noprocrast /tmp/events.log
 * Delete '#define DEBUG' to disable debug output it console.
 */

#import <Cocoa/Cocoa.h>

#define DEBUG 

#ifdef DEBUG
#define debug(fmt, ...) NSLog(fmt, ## __VA_ARGS__)
#else
#define debug(fmt, ...) 
#endif

NSString *eventDesc(CGEventType type) {
  switch(type) {
    case kCGEventMouseMoved:
      return @"moved";
    case kCGEventKeyDown:
      return @"key down";
    case kCGEventLeftMouseDown:
      return @"click";
    case kCGEventScrollWheel:
      return @"scroll";
  }
  
  return @"unknown event";
}

CGEventType lastEventType;
double lastCompressableEventTime = 0;

double lastEventTime = 0;
unsigned int recEvents = 0;

FILE *f;

struct loggedEvent {
  double diff;
  CGEventType type;
  union {
    struct {
      BOOL hasModifier;
    } keyEvent;
    struct {
      NSPoint point;
    } mouseEvent;
  } eventDets;
};

CGEventRef cfEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new]; 

  NSEvent *e = [NSEvent eventWithCGEvent:event];
  
  if(type == lastEventType && (type == kCGEventMouseMoved || type == kCGEventScrollWheel)) {
    if([e timestamp] - lastCompressableEventTime < 0.2) {
      return nil;
    } else {
      lastCompressableEventTime = [e timestamp];
    }
  } else if(type != lastEventType) {
    lastCompressableEventTime = 0;
  }
  
  if(lastEventTime == 0) {
    lastEventTime = [e timestamp];
    return nil;
  }
  
  struct loggedEvent levent;
  levent.diff = [e timestamp] - lastEventTime;
  levent.type = type;
  
  if(type == kCGEventMouseMoved || type == kCGEventLeftMouseDown || type == kCGEventScrollWheel) {
    levent.eventDets.mouseEvent.point = [e locationInWindow];
    debug(@"%@ %.0f %.0f", eventDesc(type), [e locationInWindow].x, [e locationInWindow].y);
  } else if(type == kCGEventKeyDown) {
    levent.eventDets.keyEvent.hasModifier = [e modifierFlags] != 0;
    debug(@"%@ %@", eventDesc(type), levent.eventDets.keyEvent.hasModifier ? @"modified" : @"");
  }

  NSString *activeApp = [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"];
  debug(@"active: %@", activeApp);
    
  fwrite(&levent, sizeof(struct loggedEvent), 1, f);
  fwrite([activeApp UTF8String], [activeApp length] + 1, 1, f);
  
  if(recEvents++ % 100 == 0) {
    debug(@"flushing");
    fflush(f);
  }
  
  lastEventType = type;
  lastEventTime = [e timestamp];
  
  [pool release];
  
  return nil;
}

void registerCFEvents() {
  CFMachPortRef ref = CGEventTapCreate(kCGHIDEventTap,
                                       kCGHeadInsertEventTap,
                                       kCGEventTapOptionListenOnly,
                                       CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventKeyDown) | \
                                       CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventScrollWheel),
                                       cfEventCallback,
                                       nil);

  CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, ref, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
}

int main (int argc, const char * argv[]) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new]; 
  
  if(!AXAPIEnabled()) {
    fprintf(stderr, "enable assistive shit\n");
    exit(1);
  }
    
  if(argc == 2) {
    f = fopen(argv[1], "a");
    if(!f) {
      fprintf(stderr, "couldn't open %s\n", argv[1]);
      exit(1);
    }
  } else {
    fprintf(stderr, "%s <file>\n", argv[0]);
    exit(1);
  }
  
  registerCFEvents();

  CFRunLoopRun();
  
  [pool release];
  
  return 0;
}
