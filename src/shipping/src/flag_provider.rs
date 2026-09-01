// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

use async_trait::async_trait;
use open_feature::provider::{FeatureProvider, ProviderMetadata, ResolutionDetails};
use open_feature::{EvaluationContext, EvaluationResult, StructValue};
use open_feature_flagd::{FlagdOptions, FlagdProvider};
use std::sync::{Arc, RwLock};
use std::time::Duration;
use tracing::{info, warn};

/// A `FeatureProvider` whose backing implementation can be swapped at runtime.
///
/// Starts serving on whatever `initial` provider is given (typically `NoOpProvider`) and, once
/// `spawn_flagd_connect` succeeds, upgrades in place to the real flagd provider without requiring
/// a restart. All in-flight and future evaluations transparently pick up the new provider.
pub struct SwappableFeatureProvider {
    inner: Arc<RwLock<Arc<dyn FeatureProvider>>>,
    metadata: ProviderMetadata,
}

impl SwappableFeatureProvider {
    pub fn new(initial: Arc<dyn FeatureProvider>) -> Self {
        Self {
            inner: Arc::new(RwLock::new(initial)),
            metadata: ProviderMetadata::new("swappable"),
        }
    }

    /// Spawns a background task that retries connecting to flagd forever, with capped
    /// exponential backoff, and swaps the real provider in on the first successful connection.
    pub fn spawn_flagd_connect(&self) {
        let inner = self.inner.clone();
        actix_web::rt::spawn(async move {
            let mut backoff = Duration::from_secs(1);
            const MAX_BACKOFF: Duration = Duration::from_secs(30);

            loop {
                match FlagdProvider::new(FlagdOptions {
                    cache_settings: None,
                    ..Default::default()
                })
                .await
                {
                    Ok(provider) => {
                        info!(
                            name: "shipping.flagd.connected",
                            "Connected to flagd, switching from NoOp to flagd provider"
                        );
                        *inner.write().expect("flag provider lock poisoned") = Arc::new(provider);
                        return;
                    }
                    Err(err) => {
                        warn!(
                            name: "shipping.flagd.connect_failed",
                            error = %err,
                            retry_in_secs = backoff.as_secs(),
                            "Failed to connect to flagd, continuing with NoOp provider and retrying"
                        );
                        actix_web::rt::time::sleep(backoff).await;
                        backoff = std::cmp::min(backoff * 2, MAX_BACKOFF);
                    }
                }
            }
        });
    }
}

#[async_trait]
impl FeatureProvider for SwappableFeatureProvider {
    fn metadata(&self) -> &ProviderMetadata {
        &self.metadata
    }

    async fn resolve_bool_value(
        &self,
        flag_key: &str,
        evaluation_context: &EvaluationContext,
    ) -> EvaluationResult<ResolutionDetails<bool>> {
        let provider = self.inner.read().expect("flag provider lock poisoned").clone();
        provider
            .resolve_bool_value(flag_key, evaluation_context)
            .await
    }

    async fn resolve_int_value(
        &self,
        flag_key: &str,
        evaluation_context: &EvaluationContext,
    ) -> EvaluationResult<ResolutionDetails<i64>> {
        let provider = self.inner.read().expect("flag provider lock poisoned").clone();
        provider
            .resolve_int_value(flag_key, evaluation_context)
            .await
    }

    async fn resolve_float_value(
        &self,
        flag_key: &str,
        evaluation_context: &EvaluationContext,
    ) -> EvaluationResult<ResolutionDetails<f64>> {
        let provider = self.inner.read().expect("flag provider lock poisoned").clone();
        provider
            .resolve_float_value(flag_key, evaluation_context)
            .await
    }

    async fn resolve_string_value(
        &self,
        flag_key: &str,
        evaluation_context: &EvaluationContext,
    ) -> EvaluationResult<ResolutionDetails<String>> {
        let provider = self.inner.read().expect("flag provider lock poisoned").clone();
        provider
            .resolve_string_value(flag_key, evaluation_context)
            .await
    }

    async fn resolve_struct_value(
        &self,
        flag_key: &str,
        evaluation_context: &EvaluationContext,
    ) -> EvaluationResult<ResolutionDetails<StructValue>> {
        let provider = self.inner.read().expect("flag provider lock poisoned").clone();
        provider
            .resolve_struct_value(flag_key, evaluation_context)
            .await
    }
}
