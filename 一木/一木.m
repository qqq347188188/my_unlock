
//
//  一木.m —— 由 dylib_maker.py 自动生成
//  目标 URL：https://yimuapp.com:8082/bookkeeping/user/getUserInfoById
//  用途：在 App 收到目标接口响应时，按规则改写 JSON 字段（仅供学习/自用）
//
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdarg.h>

static NSString *LogPath(void) {
    static NSString *p; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSString *d = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        p = [d stringByAppendingPathComponent:@"一木.log"];
    });
    return p;
}

static void LLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[一木_tag] %@", m);
    @try {
        NSString *line = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], m];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
        if (!fh) [line writeToFile:LogPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        else { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    } @catch (__unused NSException *e) {}
}

static NSMutableSet<NSString *> *g_seenURLs;
static id g_seenLock;
// 诊断日志：把 App 实际请求过的 URL 去重打印（每个只打一次，上限 60 条），
// 用于确认 host / path 该填什么。不需要时可整段删掉。
static void logSeenURL(NSURL *u) {
    if (!u) return;
    NSString *s = u.absoluteString;
    if (!s.length) return;
    if (!g_seenLock) g_seenLock = [NSObject new];
    @synchronized (g_seenLock) {
        if (!g_seenURLs) g_seenURLs = [NSMutableSet set];
        if ([g_seenURLs containsObject:s]) return;
        [g_seenURLs addObject:s];
        if (g_seenURLs.count <= 60) LLog(@"[URL] %@", s);
    }
}

static BOOL isTargetURL(NSURL *u) {
    if (!u) return NO;
    // HOST 两种写法都支持：只写域名（yimuapp.com），或写带端口（yimuapp.com:8082）
    // 因为 NSURL.host 不含端口，端口在 u.port 里
    NSString *want = [@"yimuapp.com:8082" lowercaseString];
    NSString *host = u.host.lowercaseString ?: @"";
    NSString *hostPort = u.port ? [NSString stringWithFormat:@"%@:%@", host, u.port] : host;
    if (![host isEqualToString:want] && ![hostPort isEqualToString:want]) return NO;
    // PATH 两边都转小写比较，大小写随便填都能命中
    return [u.path.lowercaseString containsString:[@"/bookkeeping/user/getUserInfoById" lowercaseString]];
}

static NSString *rx(NSString *s, NSString *pattern, NSString *templ) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    if (!re) return s;
    return [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:templ];
}

static NSData *patchBody(NSData *data) {
    if (!data.length) return data;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!s) { LLog(@"响应非文本，跳过 (%lu bytes)", (unsigned long)data.length); return data; }
    NSString *before = s;
    s = rx(s, @"vipType\":0", @"vipType\":1");
    s = rx(s, @"vipTime\":0,", @"vipTime\":99,");
    if ([s isEqualToString:before]) { LLog(@"未命中可改字段（响应前 300 字）：%@", before.length>300?[before substringToIndex:300]:before); return data; }
    NSData *nd = [s dataUsingEncoding:NSUTF8StringEncoding];
    LLog(@"改写完成：原 %lu 字节 -> 新 %lu 字节", (unsigned long)data.length, (unsigned long)nd.length);
    return nd;
}

// ===================== 引擎（自动生成，请勿手改） =====================
static void swizzle(Class cls, SEL sel, IMP newImp, IMP *origOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { LLog(@"[warn] 找不到方法 %@", NSStringFromSelector(sel)); return; }
    *origOut = method_getImplementation(m);
    method_setImplementation(m, newImp);
    LLog(@"[hook] %@", NSStringFromSelector(sel));
}
static void swizzleClass(Class cls, SEL sel, IMP newImp, IMP *origOut) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) { LLog(@"[warn] 找不到类方法 %@", NSStringFromSelector(sel)); return; }
    *origOut = method_getImplementation(m);
    method_setImplementation(m, newImp);
    LLog(@"[hook] +%@", NSStringFromSelector(sel));
}

typedef void (^GenComp)(NSData *, NSURLResponse *, NSError *);
static id wrapCompletion(NSURL *u, id completion) {
    if (!completion) return completion;
    GenComp orig = (GenComp)completion;
    return ^(NSData *d, NSURLResponse *resp, NSError *err) {
        NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
        LLog(@"响应 %@ status=%ld len=%lu err=%@", u.absoluteString, (long)h.statusCode, (unsigned long)d.length, err.localizedDescription ?: @"-");
        NSData *nd = (err || !d) ? d : patchBody(d);
        orig(nd, resp, err);
    };
}

static NSMutableDictionary<NSValue *, NSMutableData *> *g_acc;
static NSMutableSet<NSString *> *g_swizzledClasses;
static NSMutableDictionary<NSString *, NSValue *> *g_origData;
static NSMutableDictionary<NSString *, NSValue *> *g_origDone;
static NSValue *taskKey(id task) { return [NSValue valueWithNonretainedObject:task]; }
static IMP origOf(NSMutableDictionary<NSString *, NSValue *> *store, id self) {
    NSValue *v = store[NSStringFromClass(object_getClass(self))];
    return v ? (IMP)v.pointerValue : NULL;
}

static void my_didReceiveData(id self, SEL _cmd, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
    if (isTargetURL(task.originalRequest.URL)) {
        NSValue *k = taskKey(task);
        @synchronized (g_acc) { NSMutableData *acc = g_acc[k]; if (!acc){acc=[NSMutableData data]; g_acc[k]=acc;} [acc appendData:data]; }
        return;
    }
    IMP o = origOf(g_origData, self);
    if (o) ((void(*)(id,SEL,id,id,id))o)(self,_cmd,session,task,data);
}
static void my_didComplete(id self, SEL _cmd, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    logSeenURL(task.originalRequest.URL);
    if (isTargetURL(task.originalRequest.URL)) {
        NSMutableData *acc=nil; NSValue *k=taskKey(task);
        @synchronized(g_acc){ acc=g_acc[k]; [g_acc removeObjectForKey:k]; }
        if (acc && acc.length) {
            LLog(@"★ 攒包完成 %lu 字节，开始改写", (unsigned long)acc.length);
            NSData *patched = patchBody(acc);
            IMP oData = origOf(g_origData, self);
            if (oData) ((void(*)(id,SEL,id,id,id))oData)(self, @selector(URLSession:dataTask:didReceiveData:), session, task, patched);
        }
    }
    IMP o = origOf(g_origDone, self);
    if (o) ((void(*)(id,SEL,id,id,id))o)(self,_cmd,session,task,error);
}
static void swizzleDelegateMethods(Class cls, NSString *cn) {
    Method m1 = class_getInstanceMethod(cls, @selector(URLSession:dataTask:didReceiveData:));
    if (m1) { g_origData[cn]=[NSValue valueWithPointer:method_getImplementation(m1)]; method_setImplementation(m1,(IMP)my_didReceiveData); }
    else class_addMethod(cls, @selector(URLSession:dataTask:didReceiveData:), (IMP)my_didReceiveData, "v@:@@@");
    Method m2 = class_getInstanceMethod(cls, @selector(URLSession:task:didCompleteWithError:));
    if (m2) { g_origDone[cn]=[NSValue valueWithPointer:method_getImplementation(m2)]; method_setImplementation(m2,(IMP)my_didComplete); }
    else class_addMethod(cls, @selector(URLSession:task:didCompleteWithError:), (IMP)my_didComplete, "v@:@@@");
    LLog(@"[delegate] 已 hook 代理类 %@", cn);
}
static id (*o_dt_req_c)(id, SEL, NSURLRequest *, id);
static id my_dt_req_c(id self, SEL _cmd, NSURLRequest *req, id completion) {
    NSURL *u=req.URL; logSeenURL(u);
    if (!isTargetURL(u)) return o_dt_req_c(self,_cmd,req,completion);
    LLog(@"★ 命中请求 %@", u.absoluteString); return o_dt_req_c(self,_cmd,req,wrapCompletion(u,completion));
}
static id (*o_dt_url_c)(id, SEL, NSURL *, id);
static id my_dt_url_c(id self, SEL _cmd, NSURL *u, id completion) {
    logSeenURL(u);
    if (!isTargetURL(u)) return o_dt_url_c(self,_cmd,u,completion);
    LLog(@"★ 命中请求 %@", u.absoluteString); return o_dt_url_c(self,_cmd,u,wrapCompletion(u,completion));
}
static id (*o_session)(id, SEL, id, id, id);
static id my_session(id self, SEL _cmd, id config, id delegate, id queue) {
    id r = o_session(self,_cmd,config,delegate,queue);
    if (delegate) {
        NSString *cn = NSStringFromClass(object_getClass(delegate));
        @synchronized(g_swizzledClasses){ if (![g_swizzledClasses containsObject:cn]){ [g_swizzledClasses addObject:cn]; swizzleDelegateMethods(object_getClass(delegate), cn);} }
    }
    return r;
}
__attribute__((constructor)) static void gen_init(void) {
    LLog(@"========== 一木 已加载 ==========");
    g_acc=[NSMutableDictionary dictionary]; g_swizzledClasses=[NSMutableSet set];
    g_origData=[NSMutableDictionary dictionary]; g_origDone=[NSMutableDictionary dictionary];
    Class ss = objc_getClass("NSURLSession");
    if (ss) {
        swizzle(ss, @selector(dataTaskWithRequest:completionHandler:), (IMP)my_dt_req_c, (IMP*)&o_dt_req_c);
        swizzle(ss, @selector(dataTaskWithURL:completionHandler:), (IMP)my_dt_url_c, (IMP*)&o_dt_url_c);
        swizzleClass(ss, @selector(sessionWithConfiguration:delegate:delegateQueue:), (IMP)my_session, (IMP*)&o_session);
    }
    LLog(@"========== 就绪：打开 App 触发目标接口即可 ==========");
}
