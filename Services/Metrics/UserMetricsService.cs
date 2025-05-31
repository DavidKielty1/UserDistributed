using UserDistributed.Interfaces;
using UserDistributed.Services.Cache;
using UserDistributed.Services.Metrics.Calculations;
using UserDistributed.Services.Metrics.Models;

namespace UserDistributed.Services.Metrics;

public class UserMetricsService(
    IUserRepository userRepository,
    IRedisService redisService,
    ActivityScoreCalculator activityScoreCalculator,
    EngagementRateCalculator engagementRateCalculator,
    PerformanceIndexCalculator performanceIndexCalculator,
    ILogger<UserMetricsService> logger)
{
    private readonly SemaphoreSlim _semaphore = new(3);

    public async Task<Dictionary<string, UserMetrics>> CalculateMetricsAsync()
    {
        logger.LogInformation("Starting metrics calculation");
        var cacheKey = RedisCacheKeys.UserMetricsCache;

        // Try to get from Redis cache first
        var cachedMetrics = await redisService.GetAsync<Dictionary<string, UserMetrics>>(cacheKey);
        if (cachedMetrics != null)
        {
            logger.LogInformation("Cache hit for key: {Key}, returning {Count} metrics", cacheKey, cachedMetrics.Count);
            return cachedMetrics;
        }

        logger.LogInformation("Cache miss for key: {Key}, calculating metrics", cacheKey);
        var users = await userRepository.GetAllAsync();
        logger.LogInformation("Retrieved {Count} users for metrics calculation", users.Count());

        var metrics = new ConcurrentDictionary<string, UserMetrics>();

        // Using Parallel.ForEach with concurrent dictionary
        await Parallel.ForEachAsync(users, async (user, token) =>
        {
            await _semaphore.WaitAsync();
            try
            {
                logger.LogDebug("Processing metrics for user {UserId}", user.Id);

                // Check if metrics are already calculated for this user
                var userMetricsKey = RedisCacheKeys.UserMetrics(user.Id);
                var cachedUserMetrics = await redisService.GetAsync<UserMetrics>(userMetricsKey);
                if (cachedUserMetrics != null)
                {
                    logger.LogDebug("Cache hit for user {UserId}", user.Id);
                    metrics.TryAdd($"user_{user.Id}", cachedUserMetrics);
                    return;
                }

                logger.LogDebug("Calculating metrics for user {UserId}", user.Id);
                // Simulate some complex calculations
                await Task.Delay(50);

                // Calculate metrics using the model
                var userMetrics = new UserMetrics
                {
                    DaysActive = (DateTime.UtcNow - user.CreatedAt).TotalDays,
                    ActivityScore = activityScoreCalculator.Calculate(user),
                    EngagementRate = engagementRateCalculator.Calculate(user),
                    PerformanceIndex = performanceIndexCalculator.Calculate(user),
                    CalculatedAt = DateTime.UtcNow
                };

                logger.LogDebug("Calculated metrics for user {UserId}: ActivityScore={ActivityScore}, EngagementRate={EngagementRate}, PerformanceIndex={PerformanceIndex}",
                    user.Id, userMetrics.ActivityScore, userMetrics.EngagementRate, userMetrics.PerformanceIndex);

                // Cache individual user metrics
                await redisService.SetAsync(userMetricsKey, userMetrics, TimeSpan.FromHours(1));

                // Add to the main metrics dictionary
                metrics.TryAdd($"user_{user.Id}", userMetrics);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error calculating metrics for user {UserId}", user.Id);
            }
            finally
            {
                _semaphore.Release();
            }
        });

        var result = metrics.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);

        // Cache the complete metrics
        await redisService.SetAsync(cacheKey, result, TimeSpan.FromHours(1));
        logger.LogInformation("Completed metrics calculation. Cached {Count} metrics for key: {Key}", result.Count, cacheKey);

        return result;
    }
}