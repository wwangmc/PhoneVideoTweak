#ifndef CMD_EXE
#define CMD_EXE
#import <Foundation/Foundation.h>

// 声明一个类方法来执行命令并返回输出
NSString *PMControlRunCommand(NSString *command);
NSDictionary *PMControlReadPlistAtPath(NSString * path);
#endif
