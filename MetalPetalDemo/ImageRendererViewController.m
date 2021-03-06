//
//  ViewController.m
//  MetalPetalDemo
//
//  Created by YuAo on 25/06/2017.
//  Copyright © 2017 MetalPetal. All rights reserved.
//

#import "ImageRendererViewController.h"
#import "MetalPetalDemo-Swift.h"
#import "WeakToStrongObjectsMapTableTests.h"
#import "CameraViewController.h"
#import <sys/kdebug_signpost.h>
@import MetalPetal;
@import MetalKit;

@interface ImageRendererViewController () <MTKViewDelegate>

@property (nonatomic, weak) MTKView *renderView;

@property (nonatomic, strong) MTIContext *context;

@property (nonatomic, strong) MTIImage *inputImage;

@property (nonatomic, strong) MTISaturationFilter *saturationFilter;

@property (nonatomic, strong) MTIColorInvertFilter *colorInvertFilter;

@property (nonatomic, strong) MTIColorMatrixFilter *colorMatrixFilter;

@property (nonatomic, strong) MTIExposureFilter *exposureFilter;

@property (nonatomic, strong) MTIImage *cachedImage;

@property (nonatomic, strong) MTIMPSGaussianBlurFilter *blurFilter;

@property (nonatomic, strong) MTIMPSConvolutionFilter *convolutionFilter;

@property (nonatomic, strong) MTIMultilayerCompositingFilter *compositingFilter;

@property (nonatomic, strong) MTILensBlurFilter *lensBlurFilter;

@property (nonatomic, strong) MTICLAHEFilter *claheFilter;

@property (nonatomic, strong) MTIBlendFilter *blendFilter;

@end

@implementation ImageRendererViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [MetalPetalSwiftInterfaceTest test];
    
    //[WeakToStrongObjectsMapTableTests test];
    
    MTIContextOptions *options = [[MTIContextOptions alloc] init];
    //options.workingPixelFormat = MTLPixelFormatRGBA16Float;
    
    NSError *error;
    MTIContext *context = [[MTIContext alloc] initWithDevice:MTLCreateSystemDefaultDevice() options:options error:&error];
    self.context = context;
    
    UIImage *image = [UIImage imageNamed:@"P1040808.jpg"];
    
    MTKView *renderView = [[MTKView alloc] initWithFrame:self.view.bounds device:context.device];
    renderView.delegate = self;
    renderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    renderView.layer.opaque = NO;
    [self.view addSubview:renderView];
    self.renderView = renderView;
    
    self.saturationFilter = [[MTISaturationFilter alloc] init];
    self.colorInvertFilter = [[MTIColorInvertFilter alloc] init];
    self.colorMatrixFilter = [[MTIColorMatrixFilter alloc] init];
    self.exposureFilter = [[MTIExposureFilter alloc] init];
    self.blurFilter = [[MTIMPSGaussianBlurFilter  alloc] init];
    self.compositingFilter = [[MTIMultilayerCompositingFilter alloc] init];
    self.lensBlurFilter = [[MTILensBlurFilter alloc] init];
    self.claheFilter = [[MTICLAHEFilter alloc] init];
    
    float matrix[9] = {
        -1, 0, 1,
        -1, 0, 1,
        -1, 0, 1
    };
    self.convolutionFilter = [[MTIMPSConvolutionFilter alloc] initWithKernelWidth:3 kernelHeight:3 weights:matrix];
    //MTIImage *mtiImageFromCGImage = [[MTIImage alloc] initWithPromise:[[MTICGImagePromise alloc] initWithCGImage:image.CGImage]];
    
    id<MTLTexture> texture = [context.textureLoader newTextureWithCGImage:image.CGImage options:@{MTKTextureLoaderOptionSRGB: @(NO)} error:&error];
    MTIImage *mtiImageFromTexture = [[MTIImage alloc] initWithTexture:texture alphaType:MTIAlphaTypeAlphaIsOne];
    self.inputImage = mtiImageFromTexture;
    self.blendFilter = [[MTIBlendFilter alloc] initWithBlendMode:MTIBlendModeSaturation];
    
    self.blendFilter.inputImage = [[MTIImage alloc] initWithCGImage:[UIImage imageNamed:@"metal_blend_test_F"].CGImage options:@{MTKTextureLoaderOptionSRGB: @(NO)} alphaType:MTIAlphaTypeAlphaIsOne];
    self.blendFilter.inputBackgroundImage = [[MTIImage alloc] initWithCGImage:[UIImage imageNamed:@"metal_blend_test_B"].CGImage options:@{MTKTextureLoaderOptionSRGB: @(NO)} alphaType:MTIAlphaTypeAlphaIsOne];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
}

- (MTIImage *)saturationAndInvertTestOutputImage {
    self.saturationFilter.inputImage = self.inputImage;
    self.saturationFilter.saturation = 1.0 + sin(CFAbsoluteTimeGetCurrent() * 2.0);
    self.colorInvertFilter.inputImage = self.saturationFilter.outputImage;
    self.saturationFilter.inputImage = self.colorInvertFilter.outputImage;
    self.colorInvertFilter.inputImage = self.saturationFilter.outputImage;
    self.saturationFilter.inputImage = self.colorInvertFilter.outputImage;
    self.colorInvertFilter.inputImage = self.saturationFilter.outputImage;
    self.saturationFilter.inputImage = self.colorInvertFilter.outputImage;
    self.colorInvertFilter.inputImage = self.saturationFilter.outputImage;
    MTIImage *outputImage = self.colorInvertFilter.outputImage;
    return outputImage;
}

- (MTIImage *)colorMatrixTestOutputImage {
    float scale = sin(CFAbsoluteTimeGetCurrent() * 2.0) + 1.0;
    self.colorMatrixFilter.colorMatrix = MTIColorMatrixMakeWithExposure(scale);
    self.colorMatrixFilter.inputImage = self.inputImage;
    MTIImage *outputImage = self.colorMatrixFilter.outputImage;
    return outputImage;
}

- (MTIImage *)lensBlurTestOutputImage {
    self.lensBlurFilter.brightness = 0.3;
    self.lensBlurFilter.radius = 10 * (1.0 + sin(CFAbsoluteTimeGetCurrent() * 2.0));
    self.lensBlurFilter.inputImage = self.inputImage;
    MTIImage *outputImage = self.lensBlurFilter.outputImage;
    return outputImage;
}

- (MTIImage *)claheTestOutputImage {
    self.claheFilter.inputImage = self.inputImage;
    return self.claheFilter.outputImage;
}

- (MTIImage *)renderTargetCacheAndReuseTestOutputImage {
    MTIImage *inputImage = self.inputImage;
    self.saturationFilter.inputImage = inputImage;
    self.saturationFilter.saturation = 2.0;
    
    MTIImage *saturatedImage = self.cachedImage;
    if (!saturatedImage) {
        saturatedImage = [self.saturationFilter.outputImage imageWithCachePolicy:MTIImageCachePolicyPersistent];
        self.cachedImage = saturatedImage;
    }
    
    self.colorInvertFilter.inputImage = saturatedImage;
    self.saturationFilter.inputImage = self.colorInvertFilter.outputImage;
    self.saturationFilter.saturation = 0.0;
    MTIImage *invertedAndDesaturatedImage = self.saturationFilter.outputImage;
    
    self.saturationFilter.saturation = 0.0;
    self.saturationFilter.inputImage = saturatedImage;
    self.colorInvertFilter.inputImage = self.saturationFilter.outputImage;
    MTIImage *desaturatedAndInvertedImage = self.colorInvertFilter.outputImage;
    
    self.blendFilter.inputBackgroundImage = desaturatedAndInvertedImage;
    self.blendFilter.inputImage = invertedAndDesaturatedImage;
    return self.blendFilter.outputImage;
}

- (MTIImage *)multilayerCompositingTestOutputImage {
    self.compositingFilter.inputBackgroundImage = self.inputImage;
    self.compositingFilter.layers = @[
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(200, 200) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(900, 900) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeNormal],
                                      [[MTICompositingLayer alloc] initWithContent:self.inputImage position:CGPointMake(600, 600) size:CGSizeMake(1920/3.0, 1080/3.0) rotation:-3.14/4.0 opacity:1 blendMode:MTIBlendModeOverlay]
                                      ];
    return self.compositingFilter.outputImage;
}

- (MTIImage *)blendFilterTestOutputImage
{
    return self.blendFilter.outputImage;
}

#pragma mark ----------
- (void)drawInMTKView:(MTKView *)view {
    //https://developer.apple.com/library/content/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html
    @autoreleasepool {
        if (@available(iOS 10.0, *)) {
            kdebug_signpost_start(1, 0, 0, 0, 1);
        }
        MTIImage *outputImage = [self blendFilterTestOutputImage];
        MTIDrawableRenderingRequest *request = [[MTIDrawableRenderingRequest alloc] init];
        request.drawableProvider = self.renderView;
        request.resizingMode = MTIDrawableRenderingResizingModeAspect;
        NSError *error;
        [self.context renderImage:outputImage toDrawableWithRequest:request error:&error];
       
        if (@available(iOS 10.0, *)) {
            kdebug_signpost_start(1, 0, 0, 0, 1);
        }
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end

