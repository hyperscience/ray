# Replaced with the current commit when building the wheels.
commit = "{{RAY_COMMIT_SHA}}"
version = "2.37.0+hs0"

if __name__ == "__main__":
    print("%s %s" % (version, commit))
