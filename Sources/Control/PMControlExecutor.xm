#import "PMControlExecutor.h"
#import <roothide.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>

NSString *PMControlRunCommand(NSString *command) {
    if (![command isKindOfClass:[NSString class]] || !command.length) return nil;
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        NSLog(@"Failed to create command pipe: %s", strerror(errno));
        return nil;
    }
    // Concurrent commands must not inherit another request's pipe and keep it open.
    if (fcntl(pipefd[0], F_SETFD, FD_CLOEXEC) == -1 || fcntl(pipefd[1], F_SETFD, FD_CLOEXEC) == -1) {
        close(pipefd[0]);
        close(pipefd[1]);
        return nil;
    }
    posix_spawn_file_actions_t actions;
    int status = posix_spawn_file_actions_init(&actions);
    if (status != 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return nil;
    }
    status = posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    if (!status) status = posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    if (!status) status = posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    if (!status) status = posix_spawn_file_actions_addclose(&actions, pipefd[1]);

    pid_t pid = 0;
    const char *roothelpPath = jbroot("/usr/local/bin/phonevideo-roothelp");
    const char *argv[] = {roothelpPath, command.UTF8String, NULL};
    if (!status) status = posix_spawn(&pid, roothelpPath, &actions, NULL, (char *const *)argv, NULL);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);
    if (status != 0) {
        close(pipefd[0]);
        NSLog(@"Failed to launch roothelp: %s", strerror(status));
        return nil;
    }

    NSMutableData *output = [NSMutableData data];
    char buffer[4096];
    ssize_t bytesRead;
    while (YES) {
        bytesRead = read(pipefd[0], buffer, sizeof(buffer));
        if (bytesRead > 0) [output appendBytes:buffer length:(NSUInteger)bytesRead];
        else if (bytesRead == -1 && errno == EINTR) continue;
        else break;
    }
    BOOL readFailed = bytesRead < 0;
    close(pipefd[0]);
    int exitStatus;
    pid_t waitResult;
    do {
        waitResult = waitpid(pid, &exitStatus, 0);
    } while (waitResult == -1 && errno == EINTR);
    if (readFailed || waitResult == -1) return nil;

    // Preserve command output for non-zero command exits, as the API previously did.
    NSString *rawOutput = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    if (!rawOutput) rawOutput = [[NSString alloc] initWithData:output encoding:NSISOLatin1StringEncoding];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [rawOutput componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if (line.length && [line rangeOfString:@"SubstituteLog"].location == NSNotFound) [lines addObject:line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

NSDictionary *PMControlReadPlistAtPath(NSString *path) {
    if (![path isKindOfClass:[NSString class]] || !path.length) return nil;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}
