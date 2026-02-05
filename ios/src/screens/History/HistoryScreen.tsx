import React, {useState, useCallback} from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  Modal,
  RefreshControl,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useFocusEffect} from '@react-navigation/native';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {Measurement} from '../../types';
import {getCurrentUser, getMeasurements} from '../../services/firebase';

type FilterType = 'all' | 'extension' | 'flexion';

const HistoryScreen = () => {
  const [measurements, setMeasurements] = useState<Measurement[]>([]);
  const [filter, setFilter] = useState<FilterType>('all');
  const [selectedPhoto, setSelectedPhoto] = useState<string | null>(null);
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

  const filteredMeasurements = measurements.filter(m => {
    if (filter === 'all') return true;
    return m.type === filter;
  });

  const groupByDate = (data: Measurement[]) => {
    const groups: {[key: string]: Measurement[]} = {};
    data.forEach(m => {
      const dateKey = m.timestamp.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric',
      });
      if (!groups[dateKey]) {
        groups[dateKey] = [];
      }
      groups[dateKey].push(m);
    });
    return Object.entries(groups).map(([date, items]) => ({
      date,
      data: items,
    }));
  };

  const groupedData = groupByDate(filteredMeasurements);

  const renderMeasurementItem = ({item}: {item: Measurement}) => (
    <TouchableOpacity
      style={styles.measurementItem}
      onPress={() => item.photoUrl && setSelectedPhoto(item.photoUrl)}
      activeOpacity={0.7}>
      <View style={styles.measurementInfo}>
        <View
          style={[
            styles.typeBadge,
            item.type === 'extension'
              ? styles.extensionBadge
              : styles.flexionBadge,
          ]}>
          <Text style={styles.typeText}>
            {item.type === 'extension' ? 'EXT' : 'FLX'}
          </Text>
        </View>
        <View style={styles.measurementDetails}>
          <Text style={styles.angleText}>{item.angle}°</Text>
          <Text style={styles.timeText}>
            {item.timestamp.toLocaleTimeString('en-US', {
              hour: 'numeric',
              minute: '2-digit',
            })}
          </Text>
        </View>
      </View>
      <View style={styles.weekBadge}>
        <Text style={styles.weekText}>Week {item.weekPostOp}</Text>
      </View>
    </TouchableOpacity>
  );

  const renderDateGroup = ({
    item,
  }: {
    item: {date: string; data: Measurement[]};
  }) => (
    <View style={styles.dateGroup}>
      <Text style={styles.dateHeader}>{item.date}</Text>
      {item.data.map(measurement => (
        <View key={measurement.id}>
          {renderMeasurementItem({item: measurement})}
        </View>
      ))}
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>History</Text>
      </View>

      <View style={styles.filterContainer}>
        {(['all', 'extension', 'flexion'] as FilterType[]).map(f => (
          <TouchableOpacity
            key={f}
            style={[styles.filterButton, filter === f && styles.filterActive]}
            onPress={() => setFilter(f)}>
            <Text
              style={[
                styles.filterText,
                filter === f && styles.filterTextActive,
              ]}>
              {f === 'all' ? 'All' : f === 'extension' ? 'Extension' : 'Flexion'}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {loading ? (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>Loading...</Text>
        </View>
      ) : groupedData.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>No measurements yet</Text>
          <Text style={styles.emptySubtext}>
            Take your first measurement to see it here
          </Text>
        </View>
      ) : (
        <FlatList
          data={groupedData}
          renderItem={renderDateGroup}
          keyExtractor={item => item.date}
          contentContainerStyle={styles.listContent}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={onRefresh}
              tintColor={colors.primary}
            />
          }
        />
      )}

      <Modal
        visible={!!selectedPhoto}
        transparent
        animationType="fade"
        onRequestClose={() => setSelectedPhoto(null)}>
        <TouchableOpacity
          style={styles.modalOverlay}
          activeOpacity={1}
          onPress={() => setSelectedPhoto(null)}>
          <View style={styles.modalContent}>
            {selectedPhoto && (
              <Image
                source={{uri: selectedPhoto}}
                style={styles.fullImage}
                resizeMode="contain"
              />
            )}
            <TouchableOpacity
              style={styles.closeButton}
              onPress={() => setSelectedPhoto(null)}>
              <Text style={styles.closeButtonText}>Close</Text>
            </TouchableOpacity>
          </View>
        </TouchableOpacity>
      </Modal>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    paddingBottom: spacing.md,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
  },
  filterContainer: {
    flexDirection: 'row',
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    gap: spacing.sm,
  },
  filterButton: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: borderRadius.full,
    backgroundColor: colors.surface,
  },
  filterActive: {
    backgroundColor: colors.primary,
  },
  filterText: {
    ...typography.subhead,
    color: colors.textSecondary,
  },
  filterTextActive: {
    color: colors.text,
  },
  listContent: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
  },
  dateGroup: {
    marginBottom: spacing.lg,
  },
  dateHeader: {
    ...typography.footnote,
    color: colors.textSecondary,
    marginBottom: spacing.sm,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  measurementItem: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: colors.surface,
    borderRadius: borderRadius.md,
    padding: spacing.md,
    marginBottom: spacing.sm,
  },
  measurementInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  typeBadge: {
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
    borderRadius: borderRadius.sm,
    marginRight: spacing.md,
  },
  extensionBadge: {
    backgroundColor: colors.success + '30',
  },
  flexionBadge: {
    backgroundColor: colors.primary + '30',
  },
  typeText: {
    ...typography.caption1,
    fontWeight: '600',
    color: colors.text,
  },
  measurementDetails: {
    alignItems: 'flex-start',
  },
  angleText: {
    ...typography.title3,
    color: colors.text,
  },
  timeText: {
    ...typography.caption1,
    color: colors.textSecondary,
  },
  weekBadge: {
    backgroundColor: colors.surfaceLight,
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
    borderRadius: borderRadius.sm,
  },
  weekText: {
    ...typography.caption2,
    color: colors.textSecondary,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: spacing.xl,
  },
  emptyText: {
    ...typography.title3,
    color: colors.text,
    marginBottom: spacing.sm,
  },
  emptySubtext: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.9)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    width: '100%',
    height: '100%',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  fullImage: {
    width: '100%',
    height: '80%',
  },
  closeButton: {
    marginTop: spacing.lg,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.xl,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.lg,
  },
  closeButtonText: {
    ...typography.headline,
    color: colors.text,
  },
});

export default HistoryScreen;
