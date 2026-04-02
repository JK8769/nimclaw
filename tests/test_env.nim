import std/os
echo "Original: ", getEnv("NVIDIA_API_KEY")
putEnv("NVIDIA_API_KEY", "CORRECT_KEY_FROM_DOTENV")
echo "After putEnv: ", getEnv("NVIDIA_API_KEY")
