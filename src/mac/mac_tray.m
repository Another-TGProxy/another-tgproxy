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
    NSString *l_start;
    NSString *l_stop;
} TgwsTray;

static NSString *S (const char *s) { return s ? @(s) : @""; }

static NSMenuItem *add_item (NSMenu *menu, TgwsTrayTarget *t, NSString *title, int tag) {
    NSMenuItem *m = [[NSMenuItem alloc] initWithTitle:title
                                               action:@selector(fire:)
                                        keyEquivalent:@""];
    m.target = t;
    m.tag = tag;
    [menu addItem:m];
    return m;
}

void *mac_tray_new (MacTrayCb cb, void *user_data, const char *icon_path,
                    const char *l_open, const char *l_open_telegram,
                    const char *l_start, const char *l_stop,
                    const char *l_restart, const char *l_quit) {
    @autoreleasepool {
        TgwsTray *t = calloc (1, sizeof (TgwsTray));
        t->target = [TgwsTrayTarget new];
        t->target.cb = cb;
        t->target.user = user_data;
        t->l_start = [S (l_start) retain];
        t->l_stop = [S (l_stop) retain];

        t->item = [[[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength] retain];

        NSImage *img = nil;
        if (icon_path && icon_path[0])
            img = [[NSImage alloc] initWithContentsOfFile:@(icon_path)];
        if (!img && @available (macOS 11.0, *))
            img = [NSImage imageWithSystemSymbolName:@"arrow.left.arrow.right"
                           accessibilityDescription:@"Another TGProxy"];
        if (img) {
            img.template = YES;
            [img setSize:NSMakeSize (18, 18)];
            t->item.button.image = img;
        } else {
            t->item.button.title = @"TG";
        }

        NSMenu *menu = [[NSMenu alloc] init];
        add_item (menu, t->target, S (l_open), 0);
        add_item (menu, t->target, S (l_open_telegram), 1);
        [menu addItem:[NSMenuItem separatorItem]];
        t->toggle = add_item (menu, t->target, t->l_start, 2);
        add_item (menu, t->target, S (l_restart), 3);
        [menu addItem:[NSMenuItem separatorItem]];
        add_item (menu, t->target, S (l_quit), 4);
        t->item.menu = menu;

        return t;
    }
}

void mac_tray_update (void *tray, const char *tooltip, int running) {
    TgwsTray *t = (TgwsTray *) tray;
    if (!t) return;
    @autoreleasepool {
        t->item.button.toolTip = tooltip ? @(tooltip) : @"";
        t->toggle.title = running ? t->l_stop : t->l_start;
    }
}

void mac_tray_free (void *tray) {
    TgwsTray *t = (TgwsTray *) tray;
    if (!t) return;
    [[NSStatusBar systemStatusBar] removeStatusItem:t->item];
    [t->item release];
    [t->l_start release];
    [t->l_stop release];
    free (t);
}
