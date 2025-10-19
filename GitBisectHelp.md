# Example -- Find first commit that *removes* a given string

```bash
# HEAD is bad (missing the line), 100 commits ago is known good (contains the line).
git bisect start HEAD HEAD~100 --

# Search for the specified string in the specified file
git bisect run sh -c 'if grep -wq "7DE524332D7F9D8D008E5939" src/freeform/Freeform.xcodeproj/project.pbxproj; then 
    # Return success (string is found).
    exit 0
else
    # Return fail (string not found).
    exit 1
fi'

git bisect reset
```
