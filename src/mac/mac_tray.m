/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>
#include "mac_tray.h"

@interface TgwsTrayTarget : NSObject
@property (nonatomic, assign) MacTrayCb cb;
@property (nonatomic, assign) void *user;
@end

@implementation TgwsTrayTarget
- (void)fire:(NSMenuItem *)sender {
    if (self.cb) self.cb ((int) sender.tag, self.user);
}
@end

typedef struct {
    NSStatusItem *item;
    TgwsTrayTarget *target;
    NSMenuItem *toggle;
} TgwsTray;

static NSMenuItem *add_item (NSMenu *menu, TgwsTrayTarget *t, NSString *title, int tag) {
    NSMenuItem *m = [[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(fire:)
                                        keyEquivalent:@""];
    m.target = t;
    m.tag = tag;
    [menu addItem:m];
    return m;
}

void *mac_tray_new (MacTrayCb cb, void *user_data) {
    @autoreleasepool {
        TgwsTray *t = calloc (1, sizeof (TgwsTray));
        t->target = [TgwsTrayTarget new];
        t->target.cb = cb;
        t->target.user = user_data;

        t->item = [[[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength] retain];

        NSImage *img = nil;
        if (@available (macOS 11.0, *))
            img = [NSImage imageWithSystemSymbolName:@"arrow.left.arrow.right"
                           accessibilityDescription:@"Another TGProxy"];
        if (img) {
            img.template = YES;
            t->item.button.image = img;
        } else {
            t->item.button.title = @"TG";
        }

        NSMenu *menu = [[NSMenu alloc] init];
        add_item (menu, t->target, @"Open", 0);
        add_item (menu, t->target, @"Open in Telegram", 1);
        [menu addItem:[NSMenuItem separatorItem]];
        t->toggle = add_item (menu, t->target, @"Start", 2);
        add_item (menu, t->target, @"Restart", 3);
        [menu addItem:[NSMenuItem separatorItem]];
        add_item (menu, t->target, @"Quit", 4);
        t->item.menu = menu;

        return t;
    }
}

void mac_tray_update (void *tray, const char *tooltip, int running) {
    TgwsTray *t = (TgwsTray *) tray;
    if (!t) return;
    @autoreleasepool {
        t->item.button.toolTip = tooltip ? @(tooltip) : @"";
        t->toggle.title = running ? @"Stop" : @"Start";
    }
}

void mac_tray_free (void *tray) {
    TgwsTray *t = (TgwsTray *) tray;
    if (!t) return;
    [[NSStatusBar systemStatusBar] removeStatusItem:t->item];
    [t->item release];
    free (t);
}
