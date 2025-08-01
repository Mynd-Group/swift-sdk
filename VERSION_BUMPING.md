# Version Bumping

Uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`
- **PATCH**: Bug fixes (1.1.0 → 1.1.1)
- **MINOR**: New features (1.1.0 → 1.2.0)  
- **MAJOR**: Breaking changes (1.1.0 → 2.0.0)

## Process

1. Update version in `MyndCore.podspec`:
   ```ruby
   spec.version = "1.2.0"
   ```

2. Commit and tag:
   ```
   git add MyndCore.podspec
   git commit -m "Bump version to 1.2.0"
   git tag -a 1.2.0 -m "Release version 1.2.0"
   git push origin 1.2.0 main
   pod trunk push MyndCore.podspec --allow-warnings
   ``` 