//
//  MTITexturePool.m
//  Pods
//
//  Created by YuAo on 01/07/2017.
//
//

#import "MTITexturePool.h"
#import "MTITextureDescriptor.h"
#import "MTIPrint.h"
#import "MTILock.h"

@interface MTITexturePool ()

@property (nonatomic, strong) id<NSLocking> lock;

@property (nonatomic, strong) id<MTLDevice> device;

@property (nonatomic, strong) NSMutableDictionary<MTITextureDescriptor *, NSMutableArray<id<MTLTexture>> *> *textureCache;

- (void)returnTexture:(id<MTLTexture>)texture textureDescriptor:(MTITextureDescriptor *)textureDescriptor;

@end


@interface MTIReusableTexture ()

@property (nonatomic, strong) id<NSLocking> lock;

@property (nonatomic, copy) MTITextureDescriptor *textureDescriptor;

@property (nonatomic, weak) MTITexturePool *pool;

@property (nonatomic) NSInteger textureReferenceCount;

@property (nonatomic) BOOL valid;

@end

@implementation MTIReusableTexture

@synthesize texture = _texture;

- (instancetype)initWithTexture:(id<MTLTexture>)texture descriptor:(MTITextureDescriptor *)descriptor pool:(MTITexturePool *)pool {
    if (self = [super init]) {
        _lock = MTILockCreate();
        _textureReferenceCount = 1;
        _pool = pool;
        _texture = texture;
        _textureDescriptor = [descriptor copy];
        _valid = YES;
    }
    return self;
}

- (id<MTLTexture>)texture {
    [_lock lock];
    __auto_type texture = _texture;
    [_lock unlock];
    return texture;
}

- (BOOL)retainTexture {
    [_lock lock];
    
    if (_valid) {
        if (_textureReferenceCount <= 0) {
            [NSException raise:NSInternalInconsistencyException format:@"Retain a reusable texture after the _textureReferenceCount is less than 1."];
        }
        _textureReferenceCount += 1;
        
        [_lock unlock];
        
        return YES;
    } else {
        
        [_lock unlock];
        
        return NO;
    }
}

- (void)releaseTexture {
    id<MTLTexture> textureToReturn = nil;
    
    [_lock lock];
    
    _textureReferenceCount -= 1;
    
    NSAssert(_textureReferenceCount >= 0, @"Over release a reusable texture.");
    
    if (_textureReferenceCount == 0) {
        textureToReturn = _texture;
        _texture = nil;
        _valid = NO;
    }
    
    [_lock unlock];
    
    if (textureToReturn) {
        [_pool returnTexture:textureToReturn textureDescriptor:_textureDescriptor];
    }
}

- (void)dealloc {
    if (_texture) {
        [_pool returnTexture:_texture textureDescriptor:_textureDescriptor];
    }
}

@end


@implementation MTITexturePool

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    if (self = [super init]) {
        _lock = MTILockCreate();
        _device = device;
        _textureCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (MTIReusableTexture *)newTextureWithDescriptor:(MTITextureDescriptor *)textureDescriptor {
    [_lock lock];

    __auto_type avaliableTextures = _textureCache[textureDescriptor];
    
    id<MTLTexture> texture = nil;
    
    if (avaliableTextures.count > 0) {
        texture = [avaliableTextures lastObject];
        [avaliableTextures removeLastObject];
    }
    
    [_lock unlock];
    
    if (!texture) {
        texture = [_device newTextureWithDescriptor:[textureDescriptor newMTLTextureDescriptor]];
        MTIPrint(@"%@: New texture created.", self);
    }
    
    MTIReusableTexture *reusableTexture = [[MTIReusableTexture alloc] initWithTexture:texture descriptor:textureDescriptor pool:self];
    return reusableTexture;
}

- (void)returnTexture:(id<MTLTexture>)texture textureDescriptor:(MTITextureDescriptor *)textureDescriptor {
    [_lock lock];
    
    __auto_type avaliableTextures = _textureCache[textureDescriptor];
    if (!avaliableTextures) {
        avaliableTextures = [[NSMutableArray alloc] init];
        _textureCache[textureDescriptor] = avaliableTextures;
    }
    [avaliableTextures addObject:texture];
    
    [_lock unlock];
}

@end
