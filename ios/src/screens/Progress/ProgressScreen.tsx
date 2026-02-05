import React, {useState, useCallback} from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Dimensions,
  RefreshControl,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useFocusEffect} from '@react-navigation/native';
import Svg, {Line, Circle, Path, Text as SvgText, G} from 'react-native-svg';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {Measurement} from '../../types';
import {getCurrentUser, getMeasurements} from '../../services/firebase';

type ChartType = 'extension' | 'flexion';

const {width: SCREEN_WIDTH} = Dimensions.get('window');
const CHART_WIDTH = SCREEN_WIDTH - spacing.lg * 2;
const CHART_HEIGHT = 200;
const CHART_PADDING = {top: 20, right: 20, bottom: 40, left: 50};

const ProgressScreen = () => {
  const [measurements, setMeasurements] = useState<Measurement[]>([]);
  const [chartType, setChartType] = useState<ChartType>('extension');
  const [refreshing, setRefreshing] = useState(false);
  const [loading, setLoading] = useState(true);

  const loadData = async () => {
    try {
      const user = getCurrentUser();
      if (!user) return;

      const data = await getMeasurements(user.uid);
      setMeasurements(data);
    } catch (error) {
      console.error('Error loading measurements:', error);
    } finally {
      setLoading(false);
    }
  };

  useFocusEffect(
    useCallback(() => {
      loadData();
    }, []),
  );

  const onRefresh = async () => {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  };

  const filteredData = measurements
    .filter(m => m.type === chartType)
    .sort((a, b) => a.timestamp.getTime() - b.timestamp.getTime());

  const milestones =
    chartType === 'extension'
      ? [{value: 0, label: 'Full Extension'}]
      : [
          {value: 90, label: '90°'},
          {value: 120, label: '120°'},
          {value: 135, label: 'Full Flexion'},
        ];

  const getYRange = () => {
    if (chartType === 'extension') {
      return {min: -10, max: 30}; // Extension: 0° is goal, positive means lacking
    }
    return {min: 0, max: 150}; // Flexion: higher is better
  };

  const yRange = getYRange();
  const innerWidth = CHART_WIDTH - CHART_PADDING.left - CHART_PADDING.right;
  const innerHeight = CHART_HEIGHT - CHART_PADDING.top - CHART_PADDING.bottom;

  const getX = (index: number, total: number) => {
    if (total <= 1) return CHART_PADDING.left + innerWidth / 2;
    return CHART_PADDING.left + (index / (total - 1)) * innerWidth;
  };

  const getY = (value: number) => {
    const normalized = (value - yRange.min) / (yRange.max - yRange.min);
    return CHART_PADDING.top + innerHeight * (1 - normalized);
  };

  const generatePath = () => {
    if (filteredData.length === 0) return '';

    let path = `M ${getX(0, filteredData.length)} ${getY(filteredData[0].angle)}`;
    for (let i = 1; i < filteredData.length; i++) {
      path += ` L ${getX(i, filteredData.length)} ${getY(filteredData[i].angle)}`;
    }
    return path;
  };

  const getLatestProgress = () => {
    if (filteredData.length < 2) return null;

    const latest = filteredData[filteredData.length - 1];
    const previous = filteredData[filteredData.length - 2];
    const diff = latest.angle - previous.angle;

    if (chartType === 'extension') {
      // For extension, lower is better
      return {
        improved: diff < 0,
        change: Math.abs(diff),
      };
    }
    // For flexion, higher is better
    return {
      improved: diff > 0,
      change: Math.abs(diff),
    };
  };

  const progress = getLatestProgress();

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }>
        <View style={styles.header}>
          <Text style={styles.title}>Progress</Text>
        </View>

        <View style={styles.toggleContainer}>
          {(['extension', 'flexion'] as ChartType[]).map(type => (
            <TouchableOpacity
              key={type}
              style={[
                styles.toggleButton,
                chartType === type && styles.toggleActive,
              ]}
              onPress={() => setChartType(type)}>
              <Text
                style={[
                  styles.toggleText,
                  chartType === type && styles.toggleTextActive,
                ]}>
                {type === 'extension' ? 'Extension' : 'Flexion'}
              </Text>
            </TouchableOpacity>
          ))}
        </View>

        {progress && (
          <View style={styles.insightCard}>
            <Text style={styles.insightLabel}>Latest change</Text>
            <Text
              style={[
                styles.insightValue,
                progress.improved ? styles.improved : styles.declined,
              ]}>
              {progress.improved ? '+' : '-'}
              {progress.change}°
            </Text>
            <Text style={styles.insightDescription}>
              {progress.improved
                ? 'Great progress! Keep it up.'
                : 'Keep working on your exercises.'}
            </Text>
          </View>
        )}

        <View style={styles.chartContainer}>
          <Text style={styles.chartTitle}>
            {chartType === 'extension' ? 'Extension' : 'Flexion'} Over Time
          </Text>

          {filteredData.length === 0 ? (
            <View style={styles.emptyChart}>
              <Text style={styles.emptyText}>No data yet</Text>
              <Text style={styles.emptySubtext}>
                Take measurements to see your progress
              </Text>
            </View>
          ) : (
            <Svg width={CHART_WIDTH} height={CHART_HEIGHT}>
              {/* Y-axis grid lines */}
              {[0, 0.25, 0.5, 0.75, 1].map((ratio, i) => {
                const y = CHART_PADDING.top + innerHeight * ratio;
                const value = Math.round(
                  yRange.max - ratio * (yRange.max - yRange.min),
                );
                return (
                  <G key={i}>
                    <Line
                      x1={CHART_PADDING.left}
                      y1={y}
                      x2={CHART_WIDTH - CHART_PADDING.right}
                      y2={y}
                      stroke={colors.border}
                      strokeWidth={1}
                      strokeDasharray="4,4"
                    />
                    <SvgText
                      x={CHART_PADDING.left - 10}
                      y={y + 4}
                      fill={colors.textSecondary}
                      fontSize={10}
                      textAnchor="end">
                      {value}°
                    </SvgText>
                  </G>
                );
              })}

              {/* Milestone lines */}
              {milestones.map((milestone, i) => {
                const y = getY(milestone.value);
                if (y < CHART_PADDING.top || y > CHART_HEIGHT - CHART_PADDING.bottom)
                  return null;
                return (
                  <G key={`milestone-${i}`}>
                    <Line
                      x1={CHART_PADDING.left}
                      y1={y}
                      x2={CHART_WIDTH - CHART_PADDING.right}
                      y2={y}
                      stroke={colors.success}
                      strokeWidth={2}
                      strokeDasharray="8,4"
                    />
                    <SvgText
                      x={CHART_WIDTH - CHART_PADDING.right}
                      y={y - 5}
                      fill={colors.success}
                      fontSize={10}
                      textAnchor="end">
                      {milestone.label}
                    </SvgText>
                  </G>
                );
              })}

              {/* Data line */}
              <Path
                d={generatePath()}
                stroke={colors.primary}
                strokeWidth={3}
                fill="none"
              />

              {/* Data points */}
              {filteredData.map((m, i) => (
                <Circle
                  key={m.id}
                  cx={getX(i, filteredData.length)}
                  cy={getY(m.angle)}
                  r={6}
                  fill={colors.primary}
                  stroke={colors.background}
                  strokeWidth={2}
                />
              ))}

              {/* X-axis labels (first and last) */}
              {filteredData.length > 0 && (
                <>
                  <SvgText
                    x={CHART_PADDING.left}
                    y={CHART_HEIGHT - 10}
                    fill={colors.textSecondary}
                    fontSize={10}
                    textAnchor="start">
                    Week {filteredData[0].weekPostOp}
                  </SvgText>
                  {filteredData.length > 1 && (
                    <SvgText
                      x={CHART_WIDTH - CHART_PADDING.right}
                      y={CHART_HEIGHT - 10}
                      fill={colors.textSecondary}
                      fontSize={10}
                      textAnchor="end">
                      Week {filteredData[filteredData.length - 1].weekPostOp}
                    </SvgText>
                  )}
                </>
              )}
            </Svg>
          )}
        </View>

        <View style={styles.statsContainer}>
          <View style={styles.statCard}>
            <Text style={styles.statLabel}>Total Measurements</Text>
            <Text style={styles.statValue}>{filteredData.length}</Text>
          </View>
          {filteredData.length > 0 && (
            <>
              <View style={styles.statCard}>
                <Text style={styles.statLabel}>Best</Text>
                <Text style={styles.statValue}>
                  {chartType === 'extension'
                    ? Math.min(...filteredData.map(m => m.angle))
                    : Math.max(...filteredData.map(m => m.angle))}
                  °
                </Text>
              </View>
              <View style={styles.statCard}>
                <Text style={styles.statLabel}>Latest</Text>
                <Text style={styles.statValue}>
                  {filteredData[filteredData.length - 1].angle}°
                </Text>
              </View>
            </>
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: spacing.lg,
  },
  header: {
    marginBottom: spacing.lg,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
  },
  toggleContainer: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.xs,
    marginBottom: spacing.lg,
  },
  toggleButton: {
    flex: 1,
    paddingVertical: spacing.sm,
    alignItems: 'center',
    borderRadius: borderRadius.md,
  },
  toggleActive: {
    backgroundColor: colors.surfaceLight,
  },
  toggleText: {
    ...typography.headline,
    color: colors.textSecondary,
  },
  toggleTextActive: {
    color: colors.text,
  },
  insightCard: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    marginBottom: spacing.lg,
    alignItems: 'center',
  },
  insightLabel: {
    ...typography.footnote,
    color: colors.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: spacing.xs,
  },
  insightValue: {
    fontSize: 48,
    fontWeight: '700',
    marginBottom: spacing.xs,
  },
  improved: {
    color: colors.success,
  },
  declined: {
    color: colors.warning,
  },
  insightDescription: {
    ...typography.body,
    color: colors.textSecondary,
  },
  chartContainer: {
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    marginBottom: spacing.lg,
  },
  chartTitle: {
    ...typography.headline,
    color: colors.text,
    marginBottom: spacing.md,
  },
  emptyChart: {
    height: CHART_HEIGHT,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyText: {
    ...typography.headline,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
  },
  emptySubtext: {
    ...typography.body,
    color: colors.textTertiary,
  },
  statsContainer: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  statCard: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.md,
    alignItems: 'center',
  },
  statLabel: {
    ...typography.caption1,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
  },
  statValue: {
    ...typography.title2,
    color: colors.text,
  },
});

export default ProgressScreen;
