// File: Chams.mm
// Architecture: arm64 (iOS)
// Stealth Metal Hook with Delayed Execution

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static id<MTLDepthStencilState> g_WallhackDepthState = nil;
static IMP orig_setDepthStencilState = NULL;
static IMP orig_drawIndexedPrimitives = NULL;
static __thread id currentGameDepthState = nil;
static BOOL isHookActive = NO;

void hooked_setDepthStencilState(id self, SEL _cmd, id state) {
    currentGameDepthState = state;
    if (orig_setDepthStencilState && isHookActive) {
        ((void (*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, state);
    } else if (orig_setDepthStencilState) {
        ((void (*)(id, SEL, id))orig_setDepthStencilState)(self, _cmd, state);
    }
}

void hooked_drawIndexedPrimitives(id self, SEL _cmd, MTLPrimitiveType primitiveType, NSUInteger indexCount, MTLIndexType indexType, id indexBuffer, NSUInteger indexBufferOffset) {
    if (isHookActive && primitiveType == MTLPrimitiveTypeTriangle && indexCount > 1200 && indexCount < 16000) {
        if (g_WallhackDepthState == nil) {
            id<MTLDevice> device = [self performSelector:@selector(device)];
            if (device) {
                MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
                desc.depthCompareFunction = MTLCompareFunctionAlways;
                desc.depthWriteEnabled = NO;
                g_WallhackDepthState = [device newDepthStencilStateWithDescriptor:desc];
            }
        }
        if (g_WallhackDepthState != nil && orig_setDepthStencilState != NULL) {
            ((void (*)(id, SEL, id))orig_setDepthStencilState)(self, @selector(setDepthStencilState:), g_WallhackDepthState);
            ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, MTLIndexType, id, NSUInteger))orig_drawIndexedPrimitives)(self, _cmd, primitiveType, indexCount, indexType, indexBuffer, indexBufferOffset);
            if (currentGameDepthState != nil) {
                ((void (*)(id, SEL, id))orig_setDepthStencilState)(self, @selector(setDepthStencilState:), currentGameDepthState);
            }
            return;
        }
    }
    if (orig_drawIndexedPrimitives) {
        ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, MTLIndexType, id, NSUInteger))orig_drawIndexedPrimitives)(self, _cmd, primitiveType, indexCount, indexType, indexBuffer, indexBufferOffset);
    }
}

void activateStealthHooks() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return;
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> buffer = [queue commandBuffer];
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:16 height:16 mipmapped:NO];
        texDesc.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> dummyTex = [device newTextureWithDescriptor:texDesc];
        pass.colorAttachments[0].texture = dummyTex;
        id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];
        Class encoderClass = [encoder class];
        [encoder endEncoding];

        Method depthMethod = class_getInstanceMethod(encoderClass, @selector(setDepthStencilState:));
        if (depthMethod) {
            orig_setDepthStencilState = method_setImplementation(depthMethod, (IMP)hooked_setDepthStencilState);
        }
        SEL drawSel = @selector(drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:);
        Method drawMethod = class_getInstanceMethod(encoderClass, drawSel);
        if (drawMethod) {
            orig_drawIndexedPrimitives = method_setImplementation(drawMethod, (IMP)hooked_drawIndexedPrimitives);
        }
        
        isHookActive = YES;
    });
}

__attribute__((constructor))
static void initializeChams(void) {
    // Ждем полной загрузки игры и прохождения античит-инициализации в меню (15 секунд)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        activateStealthHooks();
    });
}
