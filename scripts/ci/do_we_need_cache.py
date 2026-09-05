from detect_runtime import (
    detect_all_runtimes,
    has_runtime,
)

from variables import CACHE_RUNTIMES

def get_cache_runtimes():
    runtimes = detect_all_runtimes()

    return {
        runtime
        for runtime in runtimes
        if runtime in CACHE_RUNTIMES
    }


def get_cache_runtimes_by_app():
    from detect_runtime import detect_apps_by_runtime

    cache_runtimes = get_cache_runtimes()
    result = {}

    for runtime in cache_runtimes:
        result[runtime] = detect_apps_by_runtime(runtime)

    return result


def needs_cache(runtime):
    if runtime not in CACHE_RUNTIMES:
        return False

    return has_runtime(runtime)


def do_we_need_cache(runtime):
    return needs_cache(runtime)

if __name__ == "__main__":
    import sys
    runtime = sys.argv[1]
    if do_we_need_cache(runtime):
        print(f"Cache required: {runtime}")
        sys.exit(0)

    print(f"Cache not required: {runtime}")
    sys.exit(1)
