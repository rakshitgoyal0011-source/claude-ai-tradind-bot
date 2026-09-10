#!/usr/bin/env sh
# Turns project.yml into DriveQuiz.xcodeproj. Run this first, on a Mac.
set -e
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed."
    echo
    echo "  brew install xcodegen"
    echo
    echo "Or build the project by hand: the README section 'Getting it into"
    echo "Xcode' lists every setting project.yml encodes."
    exit 1
fi

xcodegen generate

echo
echo "Generated DriveQuiz.xcodeproj"
echo
echo "Next:"
echo "  1. open DriveQuiz.xcodeproj"
echo "  2. Signing & Capabilities: pick your team. Change the bundle id if"
echo "     com.example.drivequiz is taken."
echo "  3. Build and run on a real iPhone. The simulator has no useful"
echo "     microphone and no car audio route, so it will not tell you much."
echo
echo "Run the logic tests first, they are faster than a device build:"
echo "  cd DriveQuizKit && swift test"
