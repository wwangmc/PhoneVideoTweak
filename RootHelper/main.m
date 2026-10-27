#include <stdio.h>
#include "TSUtil.h"
#include <roothide.h>

int main(int argc, char *argv[], char *envp[]) {
    @autoreleasepool {
        if (argc < 2 || !argv[1] || !argv[1][0]) return 64;

			// 执行传入的命令
		NSString *command = [NSString stringWithUTF8String:argv[1]];

		// 构建完整的命令参数
		NSMutableArray *args = [NSMutableArray arrayWithObject:@"-c"];

		// 将所有参数组合成一个命令字符串
		NSMutableString *fullCommand = [NSMutableString stringWithString:command];
		for (int i = 2; i < argc; i++) {
			[fullCommand appendFormat:@" %s", argv[i]];
		}
		[args addObject:fullCommand];

		NSString *sh = jbroot(@"/bin/sh");
		return spawnRoot(sh, args, nil, nil);
    }
}
