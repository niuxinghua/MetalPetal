//
//  MTIColorMatrixFilter.h
//  Pods
//
//  Created by yi chen on 2017/7/27.
//
//

#import "MTIFilter.h"
#import "MTIUnaryImageFilter.h"
#import "MTIColorMatrix.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTIColorMatrixFilter : MTIUnaryImageFilter

@property (nonatomic) MTIColorMatrix colorMatrix;

@end

@interface MTIExposureFilter : MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@property (nonatomic) float exposure;

@end

@interface MTISaturationFilter : MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@property (nonatomic) float saturation;

@end

@interface MTIColorInvertFilter : MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@end

@interface MTIOpacityFilter: MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@property (nonatomic) float opacity;

@end

@interface MTIBrightnessFilter: MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@property (nonatomic) float brightness;

@end

@interface MTIContrastFilter: MTIColorMatrixFilter

- (void)setColorMatrix:(MTIColorMatrix)colorMatrix NS_UNAVAILABLE;

@property (nonatomic) float contrast;

@end

NS_ASSUME_NONNULL_END
