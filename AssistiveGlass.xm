#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

#pragma mark - Configuration

static CGFloat const AGPressedScale = 1.15;

/*
 * "transparency 47.5%" means 47.5% transparent,
 * therefore the visible alpha is 52.5%.
 */
static CGFloat const AGPressedAlpha = 0.525;
static NSTimeInterval const AGPressDuration = 0.16;
static NSTimeInterval const AGReleaseDuration = 0.22;

static void *kAGInstalledKey = &kAGInstalledKey;
static void *kAGGlassKey = &kAGGlassKey;
static void *kAGOriginalAlphaKey = &kAGOriginalAlphaKey;

#pragma mark - Liquid (Gl)ass bridge

/*
 * We intentionally do NOT compile/link Liquid (Gl)ass source files into this
 * tweak.  Instead, when Liquid (Gl)ass is installed, we locate its
 * LGLiveBackdropView class at runtime and instantiate it.
 *
 * This keeps AssistiveGlass small and avoids duplicate copies of the Metal
 * renderer / shared runtime.
 */

static UIView *AGCreateLiquidGlass(CGRect frame) {
    Class glassClass = NSClassFromString(@"LGLiveBackdropView");
    if (!glassClass)
        return nil;

    id glass = nil;

    SEL initSelector =
        NSSelectorFromString(@"initWithFrame:groupName:filterType:");

    if ([glassClass instancesRespondToSelector:initSelector]) {
        glass = ((id (*)(id, SEL, CGRect, NSString *, NSString *))
                 objc_msgSend)([glassClass alloc],
                                initSelector,
                                frame,
                                @"AssistiveGlass",
                                @"dylv.liquidglass.refraction");
    }

    if (!glass) {
        SEL fallback =
            NSSelectorFromString(@"initWithFrame:groupName:");

        if ([glassClass instancesRespondToSelector:fallback]) {
            glass = ((id (*)(id, SEL, CGRect, NSString *))
                     objc_msgSend)([glassClass alloc],
                                    fallback,
                                    frame,
                                    @"AssistiveGlass");
        }
    }

    if (![glass isKindOfClass:[UIView class]])
        return nil;

    UIView *glassView = (UIView *)glass;
    glassView.userInteractionEnabled = NO;
    glassView.clipsToBounds = YES;

    return glassView;
}

static void AGUpdateGlass(UIView *button, UIView *glass) {
    if (!button || !glass)
        return;

    UIView *superview = button.superview;
    if (!superview)
        return;

    CGRect frame = button.frame;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    glass.frame = frame;
    glass.layer.cornerRadius = MIN(CGRectGetWidth(frame),
                                   CGRectGetHeight(frame)) * 0.5;

    if (@available(iOS 13.0, *))
        glass.layer.cornerCurve = kCACornerCurveContinuous;

    [CATransaction commit];
}

#pragma mark - Button identification

static BOOL AGLooksLikeAssistiveTouchView(UIView *view) {
    if (!view)
        return NO;

    NSString *className = NSStringFromClass(view.class);
    NSString *lower = className.lowercaseString;

    /*
     * Known/likely SpringBoard Accessibility naming patterns.
     * The fallback class-name matching is intentional because Apple has
     * changed private class names between releases.
     */
    NSArray<NSString *> *patterns = @[
        @"assistivetouch",
        @"assistive_touch",
        @"assistivetouchview",
        @"sbassistivetouch"
    ];

    for (NSString *pattern in patterns) {
        if ([lower containsString:pattern])
            return YES;
    }

    NSString *label = view.accessibilityLabel.lowercaseString;
    if ([label containsString:@"assistivetouch"])
        return YES;

    return NO;
}

static UIView *AGFindAssistiveTouchInView(UIView *root) {
    if (!root)
        return nil;

    if (AGLooksLikeAssistiveTouchView(root))
        return root;

    for (UIView *subview in root.subviews) {
        UIView *result = AGFindAssistiveTouchInView(subview);
        if (result)
            return result;
    }

    return nil;
}

static UIView *AGFindAssistiveTouch(void) {
    UIApplication *app = UIApplication.sharedApplication;

    for (UIWindow *window in app.windows.reverseObjectEnumerator) {
        UIView *candidate = AGFindAssistiveTouchInView(window);
        if (candidate)
            return candidate;
    }

    /*
     * iOS 13+ scene-based fallback.
     */
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]])
                continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows.reverseObjectEnumerator) {
                UIView *candidate = AGFindAssistiveTouchInView(window);
                if (candidate)
                    return candidate;
            }
        }
    }

    return nil;
}

#pragma mark - Press animation

static void AGAnimate(UIView *button, BOOL pressed) {
    if (!button)
        return;

    CGFloat scale = pressed ? AGPressedScale : 1.0;
    CGFloat alpha = pressed ? AGPressedAlpha : 1.0;
    NSTimeInterval duration =
        pressed ? AGPressDuration : AGReleaseDuration;

    [UIView animateWithDuration:duration
                          delay:0
         usingSpringWithDamping:pressed ? 0.72 : 0.78
          initialSpringVelocity:pressed ? 0.35 : 0.55
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        button.transform = CGAffineTransformMakeScale(scale, scale);
        button.alpha = alpha;

        UIView *glass = objc_getAssociatedObject(button, kAGGlassKey);
        if (glass) {
            glass.transform = CGAffineTransformMakeScale(scale, scale);
            glass.alpha = pressed ? 1.0 : 1.0;
        }
    } completion:nil];
}

static void AGInstallOnButton(UIView *button) {
    if (!button || objc_getAssociatedObject(button, kAGInstalledKey))
        return;

    objc_setAssociatedObject(button,
                             kAGInstalledKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSNumber *originalAlpha = @(button.alpha);
    objc_setAssociatedObject(button,
                             kAGOriginalAlphaKey,
                             originalAlpha,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *glass = AGCreateLiquidGlass(button.bounds);

    if (glass) {
        UIView *parent = button.superview;

        if (parent) {
            glass.frame = button.frame;
            glass.layer.cornerRadius =
                MIN(CGRectGetWidth(glass.bounds),
                    CGRectGetHeight(glass.bounds)) * 0.5;

            [parent insertSubview:glass belowSubview:button];

            objc_setAssociatedObject(button,
                                     kAGGlassKey,
                                     glass,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            AGUpdateGlass(button, glass);
        }
    }

    /*
     * A zero-duration long-press recognizer gives us a reliable "touch began"
     * and "touch ended" signal while leaving the original AssistiveTouch
     * interaction active.
     */
    UILongPressGestureRecognizer *gesture =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:[AGGestureTarget shared]
                    action:@selector(handleGesture:)];

    gesture.minimumPressDuration = 0.0;
    gesture.cancelsTouchesInView = NO;
    gesture.delaysTouchesBegan = NO;
    gesture.delaysTouchesEnded = NO;
    gesture.allowableMovement = 10000.0;

    [button addGestureRecognizer:gesture];

    objc_setAssociatedObject(gesture,
                             @selector(handleGesture:),
                             button,
                             OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - Gesture target

@interface AGGestureTarget : NSObject
+ (instancetype)shared;
- (void)handleGesture:(UILongPressGestureRecognizer *)gesture;
@end

@implementation AGGestureTarget

+ (instancetype)shared {
    static AGGestureTarget *target;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        target = [AGGestureTarget new];
    });

    return target;
}

- (void)handleGesture:(UILongPressGestureRecognizer *)gesture {
    UIView *button =
        objc_getAssociatedObject(gesture, @selector(handleGesture:));

    if (!button)
        return;

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            AGAnimate(button, YES);
            break;

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            AGAnimate(button, NO);
            break;

        default:
            break;
    }
}

@end

#pragma mark - SpringBoard scanner

static void AGScan(void);

static void AGScheduleScan(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                  (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AGScan();
        AGScheduleScan();
    });
}

static void AGScan(void) {
    if (![NSBundle.mainBundle.bundleIdentifier
          isEqualToString:@"com.apple.springboard"])
        return;

    UIView *button = AGFindAssistiveTouch();

    if (button)
        AGInstallOnButton(button);

    UIView *glass = button
        ? objc_getAssociatedObject(button, kAGGlassKey)
        : nil;

    if (button && glass)
        AGUpdateGlass(button, glass);
}

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
              isEqualToString:@"com.apple.springboard"])
            return;

        dispatch_async(dispatch_get_main_queue(), ^{
            AGScan();
            AGScheduleScan();
        });
    }
}
