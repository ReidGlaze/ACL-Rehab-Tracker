import React, {useEffect, useState, useCallback} from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  RefreshControl,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useNavigation, useFocusEffect} from '@react-navigation/native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {Measurement} from '../../types';
import {
  getCurrentUser,
  getMeasurements,
  getUserProfile,
  calculateWeekPostOp,
} from '../../services/firebase';

const HomeScreen = () => {
  const navigation = useNavigation();
  const [weekPostOp, setWeekPostOp] = useState(0);
  const [userName, setUserName] = useState('');
  const [latestExtension, setLatestExtension] = useState<Measurement | null>(
    null,
  );
  const [latestFlexion, setLatestFlexion] = useState<Measurement | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const loadData = async () => {
    try {
      const user = getCurrentUser();
      if (!user) return;

      // Get profile
      const profile = await getUserProfile(user.uid);
      if (profile) {
        setUserName(profile.name);
        setWeekPostOp(calculateWeekPostOp(profile.surgeryDate));
      }

      // Get latest measurements
      const measurements = await getMeasurements(user.uid);

      const extension = measurements.find(m => m.type === 'extension');
      const flexion = measurements.find(m => m.type === 'flexion');

      setLatestExtension(extension || null);
      setLatestFlexion(flexion || null);
    } catch (error) {
      console.error('Error loading home data:', error);
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

  const today = new Date().toLocaleDateString('en-US', {
    month: 'long',
    day: 'numeric',
  });

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
          <View>
            <Text style={styles.greeting}>Today</Text>
            <Text style={styles.date}>{today}</Text>
          </View>
          <View style={styles.avatarPlaceholder}>
            <Text style={styles.avatarText}>
              {userName ? userName[0].toUpperCase() : '?'}
            </Text>
          </View>
        </View>

        <View style={styles.weekCard}>
          <Text style={styles.weekLabel}>Week</Text>
          <Text style={styles.weekNumber}>{weekPostOp}</Text>
          <Text style={styles.weekSubtext}>Post-Op Recovery</Text>
        </View>

        <Text style={styles.sectionTitle}>Latest Measurements</Text>

        <View style={styles.measurementRow}>
          <View style={styles.measurementCard}>
            <Text style={styles.measurementLabel}>Extension</Text>
            <Text
              style={[
                styles.measurementValue,
                latestExtension && styles.measurementValueActive,
              ]}>
              {latestExtension ? `${latestExtension.angle}°` : '--'}
            </Text>
            <Text style={styles.measurementGoal}>Goal: 0°</Text>
          </View>

          <View style={styles.measurementCard}>
            <Text style={styles.measurementLabel}>Flexion</Text>
            <Text
              style={[
                styles.measurementValue,
                latestFlexion && styles.measurementValueActive,
              ]}>
              {latestFlexion ? `${latestFlexion.angle}°` : '--'}
            </Text>
            <Text style={styles.measurementGoal}>Goal: 135°</Text>
          </View>
        </View>

        <TouchableOpacity
          style={styles.measureButton}
          onPress={() => navigation.navigate('Measure' as never)}
          activeOpacity={0.8}>
          <Text style={styles.measureButtonText}>Measure Now</Text>
        </TouchableOpacity>

        {(latestExtension || latestFlexion) && (
          <View style={styles.lastUpdateContainer}>
            <Text style={styles.lastUpdateText}>
              Last updated:{' '}
              {(latestExtension?.timestamp || latestFlexion?.timestamp)
                ?.toLocaleDateString('en-US', {
                  month: 'short',
                  day: 'numeric',
                  hour: 'numeric',
                  minute: '2-digit',
                })}
            </Text>
          </View>
        )}
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
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  greeting: {
    ...typography.largeTitle,
    color: colors.text,
  },
  date: {
    ...typography.body,
    color: colors.textSecondary,
  },
  avatarPlaceholder: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceLight,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    ...typography.headline,
    color: colors.text,
  },
  weekCard: {
    backgroundColor: colors.success,
    borderRadius: borderRadius.lg,
    padding: spacing.xl,
    alignItems: 'center',
    marginBottom: spacing.xl,
  },
  weekLabel: {
    ...typography.body,
    color: colors.background,
    opacity: 0.8,
  },
  weekNumber: {
    fontSize: 72,
    fontWeight: '700',
    color: colors.background,
    lineHeight: 80,
  },
  weekSubtext: {
    ...typography.headline,
    color: colors.background,
    opacity: 0.9,
  },
  sectionTitle: {
    ...typography.title3,
    color: colors.text,
    marginBottom: spacing.md,
  },
  measurementRow: {
    flexDirection: 'row',
    gap: spacing.md,
    marginBottom: spacing.xl,
  },
  measurementCard: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
    padding: spacing.lg,
    alignItems: 'center',
  },
  measurementLabel: {
    ...typography.footnote,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  measurementValue: {
    fontSize: 36,
    fontWeight: '700',
    color: colors.textTertiary,
    marginBottom: spacing.xs,
  },
  measurementValueActive: {
    color: colors.text,
  },
  measurementGoal: {
    ...typography.caption1,
    color: colors.textTertiary,
  },
  measureButton: {
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
    marginBottom: spacing.lg,
  },
  measureButtonText: {
    ...typography.headline,
    color: colors.text,
  },
  lastUpdateContainer: {
    alignItems: 'center',
  },
  lastUpdateText: {
    ...typography.caption1,
    color: colors.textTertiary,
  },
});

export default HomeScreen;
