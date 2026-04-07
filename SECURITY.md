# Security Guidelines

## Cluster Information Separation

This repository contains workshop content that is deployed in two different contexts:

### 1. RHDP/Showroom Deployments (Private)
- Uses **`default-site.yml`** and **`content/antora.yml`**
- Contains real cluster URLs and namespace information
- Deployed to private workshop environments via AgnosticD
- URLs are dynamically injected by the Showroom container at runtime

### 2. GitHub Pages (Public)
- Uses **`github-site.yml`** 
- Contains ONLY placeholder values (e.g., `apps.example.openshiftapps.com`)
- Safe for public consumption at https://tosin2013.github.io/capacity-planning-lab-guide
- Does not expose any real cluster infrastructure

## Important: Do NOT Commit Real Cluster URLs

When making changes to this repository:

✅ **Safe to commit:**
- Workshop content in `content/modules/ROOT/pages/*.adoc`
- Navigation in `content/modules/ROOT/nav.adoc`
- UI customizations in `content/supplemental-ui/`
- Documentation in `README.adoc`
- Placeholder values in `github-site.yml`

⚠️ **Review before committing:**
- Changes to `content/antora.yml` - ensure cluster URLs are test/placeholder values
- Changes to `default-site.yml` - this file is only used in RHDP deployments

❌ **Never commit:**
- Real production cluster URLs
- Student namespace names (beyond generic examples)
- Admin credentials or tokens
- Environment-specific secrets

## Reporting Security Issues

If you discover exposed sensitive information in this repository:

1. **Do NOT create a public GitHub issue**
2. Contact the repository maintainer directly
3. Provide details about the exposure
4. We will patch and force-push to remove sensitive data from git history if needed

## Deployment Security

### For RHDP Instructors
- The AgnosticD workload injects real cluster URLs at deployment time
- These values are never committed to git
- Each student gets a unique namespace with proper RBAC
- Clusters are ephemeral and decommissioned after workshops

### For GitHub Pages
- The site is built using `github-site.yml` with placeholder values
- No actual cluster infrastructure is referenced
- The site is read-only documentation
- Links to "execute" commands are informational only

## Questions?

Contact the workshop maintainers if you have questions about security practices for this content.
