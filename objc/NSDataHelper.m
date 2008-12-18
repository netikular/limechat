// Created by Satoshi Nakagawa.
// You can redistribute it and/or modify it under the Ruby's license or the GPL2.

#import "NSDataHelper.h"

@implementation NSDataHelper

+ (NSData*)getLine:(NSMutableData*)data
{
  if (!data) return nil;
  
  int len = [data length];
  if (len == 0) return nil;
  
  char* buf = [data mutableBytes];
  char* p = memchr(buf, '\n', len);
  if (!p) return nil;
  
  char* end = p;
  if (end > buf && *(end-1) == '\r') {
    --end;
  }
  
  NSData* result = [NSData dataWithBytes:buf length:end-buf];
  
  char* next = p+1;
  int nextLen = len - (next - buf);
  if (end > buf && nextLen > 0) {
    memmove(buf, next, nextLen);
  }
  [data setLength:nextLen];
  
  return result;
}

@end
