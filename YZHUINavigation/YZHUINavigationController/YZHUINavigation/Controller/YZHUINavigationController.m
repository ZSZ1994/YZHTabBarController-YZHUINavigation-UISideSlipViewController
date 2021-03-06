//
//  YZHUINavigationController.m
//  YZHUINavigationController
//
//  Created by captain on 16/11/17.
//  Copyright (c) 2016年 yzh. All rights reserved.
//

#import "YZHUINavigationController.h"
#import "UINavigationItemView.h"
#import "YZHBaseAnimatedTransition.h"
#import "UIViewController+NavigationBarAndItemView.m"
#import "UIImage+TintColor.h"

#import <objc/runtime.h>

#define MIN_PERCENT_PUSH_VIEWCONTROLLER     (0.15)
#define MIN_PERCENT_POP_VIEWCONTROLLER      (0.2)

typedef void(^YZHUINavigationControllerActionCompletionBlock)(YZHUINavigationController *navigationController);


@interface UIViewController (YZHUINavigationControllerAction)

@property (nonatomic, copy) YZHUINavigationControllerActionCompletionBlock popCompletionBlock;
@property (nonatomic, copy) YZHUINavigationControllerActionCompletionBlock pushCompletionBlock;

@end

@implementation UIViewController (YZHUINavigationControllerAction)

-(void)setPopCompletionBlock:(YZHUINavigationControllerActionCompletionBlock)popCompletionBlock
{
    objc_setAssociatedObject(self, @selector(popCompletionBlock), popCompletionBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

-(YZHUINavigationControllerActionCompletionBlock)popCompletionBlock
{
    return objc_getAssociatedObject(self, _cmd);
}

-(void)setPushCompletionBlock:(YZHUINavigationControllerActionCompletionBlock)pushCompletionBlock
{
    objc_setAssociatedObject(self, @selector(pushCompletionBlock), pushCompletionBlock, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

-(YZHUINavigationControllerActionCompletionBlock)pushCompletionBlock
{
    return objc_getAssociatedObject(self, _cmd);
}

@end


@interface YZHUINavigationController () <UIGestureRecognizerDelegate,UINavigationControllerDelegate>

//创建新的navigationBarView
@property (nonatomic, strong) UINavigationBarView *navigationBarView;

//创建新的NavigationItem，此Item为rootItem，以后每个ViewController上的Item都是以此为根节点
@property (nonatomic, strong) UINavigationItemView *navigationItemRootContentView;

//ViewController上面NavigationItem对应表
@property (nonatomic, strong) NSMutableDictionary *navigationItemViewWithVCMutDict;

//创建百分比驱动动画对象
@property (nonatomic, strong) UIPercentDrivenInteractiveTransition *transition;

//是否处在手势交互的状态
@property (nonatomic, assign) BOOL isInteractive;

//push的手势
@property (nonatomic, strong) UIPanGestureRecognizer *pushPan;

//pop的收拾
@property (nonatomic, strong) UIPanGestureRecognizer *popPan;

@property (nonatomic, strong) UIViewController *lastTopVC;

@end

@implementation YZHUINavigationController


-(instancetype)init
{
    if (self = [super init]) {
        [self _setupDefaultValue];
    }
    return self;
}

-(instancetype)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) {
        [self _setupDefaultValue];
    }
    return self;
}

-(instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
        [self _setupDefaultValue];
    }
    return self;
}

-(instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
    if (self = [super initWithRootViewController:rootViewController]) {
        [self _setupDefaultValue];
    }
    return self;
}

-(instancetype)initWithRootViewController:(UIViewController *)rootViewController navigationControllerBarAndItemStyle:(UINavigationControllerBarAndItemStyle)barAndItemStyle
{
    _navigationControllerBarAndItemStyle = barAndItemStyle;
    if (self = [super initWithRootViewController:rootViewController]) {
        [self _setupDefaultValue];
    }
    return self;
}

-(void)_setupDefaultValue
{
    self.popGestureEnabled = YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.navigationControllerBarAndItemStyle == UINavigationControllerBarAndItemDefaultStyle)
    {
//        [self _printView:self.navigationBar withIndex:0];
    }
    else if (self.navigationControllerBarAndItemStyle == UINavigationControllerBarAndItemGlobalBarWithDefaultItemStyle)
    {
        [self _clearOldUINavigationBarView];
        [self _createNavigationBarView:NO];
    }
    else if (self.navigationControllerBarAndItemStyle == UINavigationControllerBarAndItemGlobalBarItemStyle)
    {
        [self _clearOldUINavigationBarView];
        [self _createNavigationItemRootContentView];
    }
    else if (self.navigationControllerBarAndItemStyle == UINavigationControllerBarAndItemViewControllerBarItemStyle)
    {
        self.navigationBar.hidden = YES;
    }
    else if (self.navigationControllerBarAndItemStyle == UINavigationControllerBarAndItemViewControllerBarWithDefaultItemStyle)
    {
        [self _clearOldUINavigationBarView];
    }
    
    [self _createPanGestureAction];
}

-(void)resetNavigationBarAndItemViewFrame:(CGRect)frame
{
    if (self.navigationBarView) {
        self.navigationBarView.frame = frame;
    }
    if (self.navigationItemRootContentView) {
        self.navigationItemRootContentView.frame = self.navigationBarView.bounds;
    }
    [self.navigationItemViewWithVCMutDict enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, UINavigationItemView * _Nonnull obj, BOOL * _Nonnull stop) {
        obj.frame = self.navigationItemRootContentView.bounds;
    }];
}

//创建事件处理
-(UIPercentDrivenInteractiveTransition*)transition
{
    if (_transition == nil) {
        _transition = [[UIPercentDrivenInteractiveTransition alloc] init];
    }
    return _transition;
}

-(void)_createPanGestureAction
{
    self.isInteractive = NO;
    
    self.pushPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePushAction:)];
    self.pushPan.delegate = self;
    self.pushPan.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.pushPan];
    
    self.popPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_handlePopAction:)];
    self.popPan.delegate = self;
    self.popPan.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:self.popPan];
    
    self.delegate = self;
}

-(void)_handlePushAction:(UIScreenEdgePanGestureRecognizer*)sender
{
    CGFloat tx = [sender translationInView:self.view].x;
    CGFloat percent = tx / CGRectGetWidth(self.view.frame);
    CGFloat vx = [sender velocityInView:self.view].x;
    
    percent = - MIN(percent, 0);
    
//    NSLog(@"percent=%f",percent);
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.isInteractive = YES;
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:pushNextViewControllerForViewController:)]) {
            UIViewController *nextVC = [self.pushVCDelegate YZHUINavigationController:self pushNextViewControllerForViewController:self.viewControllers.lastObject];
            [self pushViewController:nextVC animated:YES];
        }
    }
    else if (sender.state == UIGestureRecognizerStateChanged)
    {
        [self.transition updateInteractiveTransition:percent];
    }
    else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled)
    {
        if (vx > 0 || tx >= 0 || percent < MIN_PERCENT_PUSH_VIEWCONTROLLER) {//
            [self.transition cancelInteractiveTransition];
        }else{
            [self.transition finishInteractiveTransition];
        }
        self.isInteractive = NO;
    }
}

-(void)_handlePopAction:(UIScreenEdgePanGestureRecognizer*)sender
{
    CGFloat tx = [sender translationInView:self.view].x;
    CGFloat percent = tx / CGRectGetWidth(self.view.frame);
    CGFloat vx = [sender velocityInView:self.view].x;
    
    //    NSLog(@"tx=%f,percent=%f,vx=%f",tx,percent,vx);
    percent = MAX(percent, 0);
//    NSLog(@"percent=%f",percent);
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.isInteractive = YES;
        [self popViewControllerAnimated:YES];
    }else if (sender.state == UIGestureRecognizerStateChanged) {
        [self.transition updateInteractiveTransition:percent];
    }else if (sender.state == UIGestureRecognizerStateEnded || sender.state == UIGestureRecognizerStateCancelled) {
        if (vx < 0 || percent < MIN_PERCENT_POP_VIEWCONTROLLER) {//
            [self.transition cancelInteractiveTransition];
        }else{
            [self.transition finishInteractiveTransition];
        }
        self.isInteractive = NO;
    }
}

#pragma mark UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)panGestureRecognizer
{
    CGPoint velocity = [panGestureRecognizer velocityInView:self.view];
    if (panGestureRecognizer == self.pushPan) {
        UIViewController *topVC = self.viewControllers.lastObject;
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:pushNextViewControllerForViewController:)]) {
            UIViewController *nextVC = [self.pushVCDelegate YZHUINavigationController:self pushNextViewControllerForViewController:topVC];
            return nextVC != nil && velocity.x < 0;
        }
        return NO;
    }
    else
    {
        if (self.popGestureEnabled == NO) {
            return NO;
        }
        else {
            YZHUIViewController *topVC = (YZHUIViewController *)self.viewControllers.lastObject;
            if (!topVC.popGestureEnabled) {
                return NO;
            }
        }
        return self.viewControllers.count > 1 && velocity.x > 0;
    }
}

#pragma mark UINavigationControllerDelegate
-(void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
}

-(void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (self.lastTopVC == viewController) {
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:didPushViewController:)]) {
            [self.pushVCDelegate YZHUINavigationController:self didPushViewController:viewController];
        }
        if (self.lastTopVC.pushCompletionBlock) {
            self.lastTopVC.pushCompletionBlock(self);
        }
    }
    else
    {
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:didPopViewController:)]) {
            [self.pushVCDelegate YZHUINavigationController:self didPopViewController:self.lastTopVC];
        }
        if (self.lastTopVC.popCompletionBlock) {
            self.lastTopVC.popCompletionBlock(self);
        }
    }
    self.lastTopVC = nil;

}

-(id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animationController
{
    return self.isInteractive ? self.transition : nil;
}

-(id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)fromVC toViewController:(UIViewController *)toVC
{    
    if (operation == UINavigationControllerOperationPush) {
        self.lastTopVC = toVC;
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:willPushViewController:)]) {
            [self.pushVCDelegate YZHUINavigationController:self willPushViewController:toVC];
        }
    }
    else if (operation == UINavigationControllerOperationPop)
    {
        self.lastTopVC = fromVC;
        if ([self.pushVCDelegate respondsToSelector:@selector(YZHUINavigationController:willPopViewController:)]) {
            [self.pushVCDelegate YZHUINavigationController:self willPopViewController:fromVC];
        }
    }
    
    return [YZHBaseAnimatedTransition navigationController:self animationControllerForOperation:operation animatedTransitionStyle:YZHNavigationAnimatedTransitionStyleDefault];
}

#pragma mark override

-(void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if (!animated) {
        UIViewController *fromVC = self.topViewController;
         [self setNavigationItemViewAlpha:0 minToHidden:YES forViewController:fromVC];
    }
    [super pushViewController:viewController animated:animated];
}

//- (UIViewController *)popViewControllerAnimated:(BOOL)animated
//{
//    return [super popViewControllerAnimated:animated];
//}
//
//- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
//{
//    return [super popToViewController:viewController animated:animated];
//}
//
//- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated
//{
//    return [super popToRootViewControllerAnimated:animated];
//}

//自定义
-(void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void(^)(YZHUINavigationController *navigationController))completion
{
    viewController.pushCompletionBlock = completion;
    [self pushViewController:viewController animated:animated];
    if (!animated) {
        viewController.pushCompletionBlock = nil;
        if (completion) {
            completion(self);
        }
    }
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated completion:(void(^)(YZHUINavigationController *navigationController))completion
{
    UIViewController *VC = [super popViewControllerAnimated:animated];
    VC.popCompletionBlock = completion;
    return VC;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void(^)(YZHUINavigationController *navigationController))completion
{
    UIViewController *topVC = self.topViewController;
    topVC.popCompletionBlock = completion;
    NSArray *VCs = [super popToViewController:viewController animated:animated];
    return VCs;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated completion:(void(^)(YZHUINavigationController *navigationController))completion
{
    UIViewController *topVC = self.topViewController;
    topVC.popCompletionBlock = completion;
    NSArray *VCs = [super popToRootViewControllerAnimated:animated];
    return VCs;
}

//清空原有的navigationBar
-(void)_clearOldUINavigationBarView
{
    [self.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    [self.navigationBar setShadowImage:[UIImage new]];
}

//创建新的navigationBarView
-(UINavigationBarView*)_createNavigationBarView:(BOOL)atTop
{
    if (!IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_BAR_STYLE(self.navigationControllerBarAndItemStyle)) {
        return nil;
    }
    if (_navigationBarView == nil) {
        CGRect frame =  CGRectMake(SAFE_X, -STATUS_BAR_HEIGHT, SAFE_WIDTH, STATUS_NAV_BAR_HEIGHT);
        _navigationBarView = [[UINavigationBarView alloc] initWithFrame:frame];
//        _navigationBarView.frame = frame;
        _navigationBarView.style = UIBarViewStyleNone;
        if (atTop) {
            [self.navigationBar addSubview:_navigationBarView];
        }
        else {
            if (IS_AVAILABLE_NSSET_OBJ(self.navigationBar.subviews)) {
                UIView *first = [self.navigationBar.subviews firstObject];
                [first addSubview:_navigationBarView];
//                [self.navigationBar insertSubview:_navigationBarView atIndex:0];
            }
            else {
                [self.navigationBar addSubview:_navigationBarView];
            }
        }
    }
    return _navigationBarView;
}

-(UINavigationItemView*)_createNavigationItemRootContentView
{
    if (!IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        return nil;
    }
    [self _createNavigationBarView:YES];
    if (_navigationItemRootContentView == nil) {
        _navigationItemRootContentView = [[UINavigationItemView alloc] init];
        _navigationItemRootContentView.frame = self.navigationBarView.bounds;
        [self.navigationBarView addSubview:_navigationItemRootContentView];
    }
    return _navigationItemRootContentView;
}

-(NSMutableDictionary*)navigationItemViewWithVCMutDict
{
    if (_navigationItemViewWithVCMutDict == nil) {
        _navigationItemViewWithVCMutDict = [NSMutableDictionary dictionary];
    }
    return _navigationItemViewWithVCMutDict;
}

-(NSString*)getKeyFromVC:(UIViewController*)viewController
{
    return [[NSString alloc] initWithFormat:@"%p",viewController];
}

//在viewController初始化的时候调用，此函数仅仅是创建了一个NavigationItemView，在push的时候添加
-(void)createNewNavigationItemViewForViewController:(UIViewController*)viewController
{
    if (viewController == nil) {
        return;
    }
    
    if (!IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        return;
    }
    
    UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
    
    if (navigationItemView == nil) {
        navigationItemView = [[UINavigationItemView alloc] initWithFrame:self.navigationItemRootContentView.bounds];
        
        [self.navigationItemViewWithVCMutDict setObject:navigationItemView forKey:[self getKeyFromVC:viewController]];

        [self addNewNavigationItemViewForViewController:viewController];
    }
}

-(void)addNewNavigationItemViewForViewController:(UIViewController*)viewController
{
    [self _doCheckNavigationItemView];
    UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
    navigationItemView.frame = self.navigationItemRootContentView.bounds;
    [navigationItemView removeFromSuperview];
    [self.navigationItemRootContentView addSubview:navigationItemView];

}

//在viewController pop完成的时候调用，
-(void)removeNavigationItemViewForViewController:(UIViewController*)viewController
{
    if (viewController == nil) {
        return;
    }
    UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
    if (navigationItemView == nil) {
        return;
    }
    [self _removeNavigationItemView:navigationItemView];
    
    [self _doCheckNavigationItemView];

}

-(void)_doCheckNavigationItemView
{
    NSMutableDictionary *outMutDict = [self.navigationItemViewWithVCMutDict mutableCopy];
    [self.viewControllers enumerateObjectsUsingBlock:^(__kindof UIViewController * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *key = [self getKeyFromVC:obj];
        if ([outMutDict objectForKey:key]) {
            [outMutDict removeObjectForKey:key];
        }
    }];
    [outMutDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, UINavigationItemView * _Nonnull obj, BOOL * _Nonnull stop) {
        [self _removeNavigationItemView:obj];
    }];
}

-(void)_removeNavigationItemView:(UINavigationItemView*)navigationItemView
{
    if (navigationItemView == nil) {
        return;
    }
    [self.navigationItemViewWithVCMutDict enumerateKeysAndObjectsUsingBlock:^(id key, UINavigationItemView *itemView, BOOL *stop) {
        if (itemView == navigationItemView) {
            [self.navigationItemViewWithVCMutDict removeObjectForKey:key];
            *stop = YES;
        }
    }];
    [navigationItemView removeFromSuperview];
}

-(void)setNavigationBarViewBackgroundColor:(UIColor *)navigationBarViewBackgroundColor
{
    _navigationBarViewBackgroundColor = navigationBarViewBackgroundColor;
    if (self.navigationBarView != nil) {
        self.navigationBarView.backgroundColor = navigationBarViewBackgroundColor;
    }
    else
    {
        self.navigationBar.barTintColor = navigationBarViewBackgroundColor;
    }
}

-(void)_printView:(UIView*)view withIndex:(NSInteger)index
{
    NSString *format = @"";
    for (int i = 0; i < index; ++i) {
        format = [NSString stringWithFormat:@"%@-",format];
    }
    NSLog(@"%@view=%@",format,view);
    for (UIView *subView in view.subviews) {
        [self _printView:subView withIndex:index+1];
    }
}

-(void)setNavigationBarBottomLineColor:(UIColor *)navigationBarBottomLineColor
{
    _navigationBarBottomLineColor = navigationBarBottomLineColor;
    if (self.navigationBarView != nil) {
        self.navigationBarView.bottomLine.backgroundColor = navigationBarBottomLineColor;
    }
    else {
        if (navigationBarBottomLineColor) {
            UIImage *image = [[UIImage new] createImageWithSize:CGSizeMake(self.navigationBar.bounds.size.width, SINGLE_LINE_WIDTH) tintColor:navigationBarBottomLineColor];
            [self.navigationBar setShadowImage:image];
        }
        else {
            [self.navigationBar setShadowImage:nil];
        }
    }
}

//-(UIColor*)navigationBarViewBackgroundColor
//{
//    if (self.navigationBarView != nil) {
//        return self.navigationBarView.backgroundColor;
//    }
//    return self.navigationBar.barTintColor;
//}

-(void)setNavigationBarViewAlpha:(CGFloat)navigationBarViewAlpha
{
    _navigationBarViewAlpha = navigationBarViewAlpha;
    if (self.navigationBarView != nil) {
        self.navigationBarView.alpha = navigationBarViewAlpha;
        if (navigationBarViewAlpha <= MIN_ALPHA_TO_HIDDEN) {
            self.navigationBarView.hidden = YES;
        }
        else {
            self.navigationBarView.hidden = NO;
        }
    }
    else
    {
        self.navigationBar.alpha = navigationBarViewAlpha;
        if (navigationBarViewAlpha <= MIN_ALPHA_TO_HIDDEN) {
            self.navigationBar.hidden = YES;
        }
        else {
            self.navigationBar.hidden = NO;
        }
    }
}

-(void)setBarViewStyle:(UIBarViewStyle)barViewStyle
{
    _barViewStyle = barViewStyle;
    if (self.navigationBarView != nil) {
        self.navigationBarView.style = barViewStyle;
    }
}

//设置NavigationItemView相关
-(void)setNavigationItemViewAlpha:(CGFloat)alpha minToHidden:(BOOL)minToHidden forViewController:(UIViewController*)viewController
{
    UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
    if (navigationItemView) {
        navigationItemView.alpha = alpha;
        if (minToHidden) {
            if (alpha <= MIN_ALPHA_TO_HIDDEN) {
                navigationItemView.hidden = YES;
            }
            else {
                navigationItemView.hidden = NO;
            }
        }
    }
}

-(void)setNavigationItemViewTransform:(CGAffineTransform)transform forViewController:(UIViewController*)viewController
{
    UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
    if (navigationItemView) {
        navigationItemView.t = transform;
    }
}

-(void)setNavigationItemTitle:(NSString*)title forViewController:(UIViewController*)viewController
{
    if (IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
        [navigationItemView setTitle:title];
    }
    else
    {
        self.title = title;
    }
}

-(void)setNavigationItemTitleTextAttributes:(NSDictionary<NSAttributedStringKey, id>*)textAttributes forViewController:(UIViewController*)viewController
{
    if (IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
        navigationItemView.titleTextAttributes = textAttributes;
    }
}

-(void)addNavigationItemViewLeftButtonItems:(NSArray*)leftButtonItems isReset:(BOOL)reset forViewController:(UIViewController *)viewController
{
    if (IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
        [navigationItemView setLeftButtonItems:leftButtonItems isReset:reset];
    }
    else if (IS_SYSTEM_DEFAULT_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle))
    {
        self.navigationItem.leftBarButtonItems = leftButtonItems;
    }
}

-(void)addNavigationItemViewRightButtonItems:(NSArray*)rightButtonItems isReset:(BOOL)reset forViewController:(UIViewController *)viewController
{
    if (IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle)) {
        UINavigationItemView *navigationItemView = [self.navigationItemViewWithVCMutDict objectForKey:[self getKeyFromVC:viewController]];
        [navigationItemView setRightButtonItems:rightButtonItems isReset:reset];
    }
    else if (IS_SYSTEM_DEFAULT_UINAVIGATIONCONTROLLER_ITEM_STYLE(self.navigationControllerBarAndItemStyle))
    {
        self.navigationItem.rightBarButtonItems = rightButtonItems;
    }
}

-(void)addNavigationBarCustomView:(UIView*)customView
{
    if (IS_CUSTOM_GLOBAL_UINAVIGATIONCONTROLLER_BAR_STYLE(self.navigationControllerBarAndItemStyle)) {
        if (customView) {
            [self.navigationBarView addSubview:customView];
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}



@end
