//
//  MTIImageRenderingContext.m
//  Pods
//
//  Created by YuAo on 25/06/2017.
//
//

#import "MTIImageRenderingContext.h"
#import "MTIContext.h"
#import "MTIImage.h"
#import "MTIImage+Promise.h"
#import "MTIWeakToStrongObjectsMapTable.h"
#import "MTIError.h"

@interface MTIImageRenderingDependencyGraph : NSObject

@property (nonatomic,strong) NSMapTable<id<MTIImagePromise>,NSMutableArray<id<MTIImagePromise>> *> *promiseDenpendentsTable;

@end

@implementation MTIImageRenderingDependencyGraph

- (instancetype)init {
    if (self = [super init]) {
        _promiseDenpendentsTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory|NSMapTableObjectPointerPersonality valueOptions:NSMapTableStrongMemory];
    }
    return self;
}

- (void)addDependenciesForImage:(MTIImage *)image {
    __auto_type dependencies = image.promise.dependencies;
    for (MTIImage *dependency in dependencies) {
        __auto_type dependents = [self.promiseDenpendentsTable objectForKey:dependency.promise];
        if (!dependents) {
            dependents = [NSMutableArray array];
            [self.promiseDenpendentsTable setObject:dependents forKey:dependency.promise];
        }
        [dependents addObject:image.promise];
        [self addDependenciesForImage:dependency];
    }
}

- (NSInteger)dependentCountForPromise:(id<MTIImagePromise>)promise {
    return [self.promiseDenpendentsTable objectForKey:promise].count;
}

- (void)removeDependent:(id<MTIImagePromise>)dependent forPromise:(id<MTIImagePromise>)promise {
    __auto_type dependents = [self.promiseDenpendentsTable objectForKey:promise];
    NSAssert(dependents, @"");
    NSAssert([dependents containsObject:dependent], @"");
    NSUInteger index = [dependents indexOfObject:dependent];
    [dependents removeObjectAtIndex:index];
}

@end

@interface MTITransientImagePromiseResolution: NSObject <MTIImagePromiseResolution>

@property (nonatomic,copy) void (^invalidationHandler)(id);

@end

@implementation MTITransientImagePromiseResolution

@synthesize texture = _texture;

- (instancetype)initWithTexture:(id<MTLTexture>)texture invalidationHandler:(void (^)(id))invalidationHandler {
    if (self = [super init]) {
        _invalidationHandler = [invalidationHandler copy];
        _texture = texture;
    }
    return self;
}

- (void)markAsConsumedBy:(id)consumer {
    self.invalidationHandler(consumer);
    self.invalidationHandler = nil;
}

- (void)dealloc {
    NSAssert(self.invalidationHandler == nil, @"");
}

@end

@interface MTIPersistImageResolutionHolder : NSObject

@property (nonatomic,strong) MTIImagePromiseRenderTarget *renderTarget;

@end

@implementation MTIPersistImageResolutionHolder

- (instancetype)initWithRenderTarget:(MTIImagePromiseRenderTarget *)renderTarget {
    if (self = [super init]) {
        _renderTarget = renderTarget;
        [renderTarget retainTexture];
    }
    return self;
}

- (void)dealloc {
    [_renderTarget releaseTexture];
}

@end


MTIContextPromiseAssociatedValueTableName const MTIContextPromiseRenderTargetTable = @"MTIContextPromiseRenderTargetTable";
MTIContextImageAssociatedValueTableName const MTIContextImagePersistentResolutionHolderTable = @"MTIContextImagePersistentResolutionHolderTable";

@interface MTIImageRenderingContext ()

@property (nonatomic,strong) MTIImageRenderingDependencyGraph *dependencyGraph;

@property (nonatomic,strong) NSHashTable<id<MTIImagePromise>> *resolvedPromises;

@end

@implementation MTIImageRenderingContext

- (void)dealloc {
    if (self.commandBuffer.status == MTLCommandBufferStatusNotEnqueued || self.commandBuffer.status == MTLCommandBufferStatusEnqueued) {
        [self.commandBuffer commit];
    }
}

- (instancetype)initWithContext:(MTIContext *)context {
    if (self = [super init]) {
        _context = context;
        _commandBuffer = [context.commandQueue commandBuffer];
        _resolvedPromises = [NSHashTable hashTableWithOptions:NSHashTableWeakMemory|NSHashTableObjectPointerPersonality];
    }
    return self;
}

- (id<MTIImagePromiseResolution>)resolutionForImage:(MTIImage *)image error:(NSError * _Nullable __autoreleasing *)inOutError {
    if (image == nil) {
        [NSException raise:NSInvalidArgumentException format:@"%@: Application is requesting a resolution of a nil image.", self];
    }
    
    BOOL isRootImage = NO;
    
    if (!self.dependencyGraph) {
        //create dependency graph
        MTIImageRenderingDependencyGraph *dependencyGraph = [[MTIImageRenderingDependencyGraph alloc] init];
        [dependencyGraph addDependenciesForImage:image];
        self.dependencyGraph = dependencyGraph;
        
        isRootImage = YES;
    }
    
    MTIImageRenderingDependencyGraph *dependencyGraph = self.dependencyGraph;
    id<MTIImagePromise> promise = image.promise;
    NSAssert(image.promise, @"");

    MTIImagePromiseRenderTarget *renderTarget = nil;
    if ([self.resolvedPromises containsObject:promise]) {
        //resolved
        renderTarget = [self.context valueForPromise:promise inTable:MTIContextPromiseRenderTargetTable];
        NSAssert(renderTarget != nil, @"");
        NSAssert(renderTarget.texture != nil, @"");
    } else {
        renderTarget = [self.context valueForPromise:promise inTable:MTIContextPromiseRenderTargetTable];
        BOOL renderTargetIsValid = NO;
        if (renderTarget) {
            if ([renderTarget retainTexture]) {
                NSAssert(renderTarget != nil, @"");
                NSAssert(renderTarget.texture != nil, @"");
                renderTargetIsValid = YES;
            }
        }
        if (!renderTargetIsValid) {
            NSError *error;
            renderTarget = [promise resolveWithContext:self error:&error];
            if (error) {
                if (inOutError) {
                    *inOutError = error;
                }
                //clean up
                [renderTarget releaseTexture];
                for (id<MTIImagePromise> promise in self.resolvedPromises) {
                    if ([dependencyGraph dependentCountForPromise:promise] != 0) {
                        MTIImagePromiseRenderTarget *target = [self.context valueForPromise:promise inTable:MTIContextPromiseRenderTargetTable];
                        [target releaseTexture];
                    }
                }
                return nil;
            }
            NSAssert(renderTarget != nil, @"");
            NSAssert(renderTarget.texture != nil, @"");
            [self.context setValue:renderTarget forPromise:promise inTable:MTIContextPromiseRenderTargetTable];
        }
        [self.resolvedPromises addObject:promise];
    }
    
    if (image.cachePolicy == MTIImageCachePolicyPersistent) {
        MTIPersistImageResolutionHolder *persistResolution = [self.context valueForImage:image inTable:MTIContextImagePersistentResolutionHolderTable];
        if (!persistResolution) {
            persistResolution = [[MTIPersistImageResolutionHolder alloc] initWithRenderTarget:renderTarget];
            [self.context setValue:persistResolution forImage:image inTable:MTIContextImagePersistentResolutionHolderTable];
        }
    }
    
    if (isRootImage) {
        return [[MTITransientImagePromiseResolution alloc] initWithTexture:renderTarget.texture invalidationHandler:^(id consumer) {
            [renderTarget releaseTexture];
        }];
    } else {
        return [[MTITransientImagePromiseResolution alloc] initWithTexture:renderTarget.texture invalidationHandler:^(id consumer){
            [dependencyGraph removeDependent:consumer forPromise:promise];
            if ([dependencyGraph dependentCountForPromise:promise] == 0) {
                [renderTarget releaseTexture];
            }
        }];
    }
}

@end

@interface MTIImageBuffer () <MTIImagePromise>

@property (nonatomic,strong) MTIImage *image;

@property (nonatomic,strong) MTIPersistImageResolutionHolder *resolution;

@end

@implementation MTIImageBuffer

@synthesize dimensions = _dimensions;
@synthesize alphaType = _alphaType;

+ (MTIImage *)bufferForImage:(MTIImage *)image {
    return [[MTIImage alloc] initWithPromise:[[MTIImageBuffer alloc] initWithImage:image] samplerDescriptor:image.samplerDescriptor cachePolicy:MTIImageCachePolicyPersistent];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSArray<MTIImage *> *)dependencies {
    return @[];
}

- (instancetype)initWithImage:(MTIImage *)image {
    if (self = [super init]) {
        NSAssert(image.cachePolicy == MTIImageCachePolicyPersistent, @"Invalid cache policy.");
        _dimensions = image.promise.dimensions;
        _image = image;
        _alphaType = image.alphaType;
    }
    return self;
}

- (MTIImagePromiseRenderTarget *)resolveWithContext:(MTIImageRenderingContext *)renderingContext error:(NSError * _Nullable __autoreleasing *)error {
    if (!_resolution) {
        MTIPersistImageResolutionHolder *persistResolution = [renderingContext.context valueForImage:_image inTable:MTIContextImagePersistentResolutionHolderTable];
        if (!persistResolution) {
            if (error) {
                *error = [NSError errorWithDomain:MTIErrorDomain code:MTIErrorFailedToGetRenderedBuffer userInfo:@{}];
            }
            return nil;
        }
        _resolution = persistResolution;
        _image = nil;
    }
    return _resolution.renderTarget;
}

@end

