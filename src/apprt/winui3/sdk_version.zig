//! Single source of truth for Windows App SDK version.
//!
//! Rule: bootstrap_majorminor ≤ bundled DLL version (forward compat OK).
//! DDLM must be installed for the bootstrap version, not the DLL version.
//! Example: bootstrap 1.4 + bundled DLLs 1.6 = works (DDLM 4000 required).
//!          bootstrap 1.6 + bundled DLLs 1.6 = fails if DDLM 6000 not installed.

/// Version passed to MddBootstrapInitialize.
/// This determines which DDLM package is required on the user's machine.
/// Keep this at the lowest version whose DDLM is widely installed.
pub const bootstrap_majorminor: u32 = 0x00010006; // 1.6

/// Version tag for MddBootstrapInitialize (empty = stable release).
pub const bootstrap_version_tag = [_:0]u16{};

/// Minimum runtime version (0 = any).
pub const runtime_version: u64 = 0;

/// NuGet package version string (used in .csproj and scripts).
/// This is the version of the actual DLLs we bundle.
pub const nuget_version = "1.6.250108002";

/// Human-readable label for error messages.
pub const display_version = "1.6";
