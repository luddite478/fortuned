#ifndef NIYYA_LOG_H
#define NIYYA_LOG_H

#ifdef prnt
#undef prnt
#endif
#ifdef prnt_err
#undef prnt_err
#endif

#ifndef LOG_TAG
#define LOG_TAG "NATIVE"
#endif

#ifdef __APPLE__
    #include <os/log.h>
    #define prnt(fmt, ...) os_log(OS_LOG_DEFAULT, "%{public}s: " fmt, LOG_TAG, ##__VA_ARGS__)
    #define prnt_err(fmt, ...) os_log_error(OS_LOG_DEFAULT, "%{public}s: " fmt, LOG_TAG, ##__VA_ARGS__)
#elif defined(__ANDROID__)
    #include <android/log.h>
    #define prnt(fmt, ...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, fmt, ##__VA_ARGS__)
    #define prnt_err(fmt, ...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, fmt, ##__VA_ARGS__)
#else
    #include <stdio.h>
    #define prnt(fmt, ...) printf("%s: " fmt "\n", LOG_TAG, ##__VA_ARGS__)
    #define prnt_err(fmt, ...) fprintf(stderr, "%s: " fmt "\n", LOG_TAG, ##__VA_ARGS__)
#endif

#endif


