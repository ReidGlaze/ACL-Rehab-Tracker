import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import {SafeAreaView} from 'react-native-safe-area-context';
import {useNavigation} from '@react-navigation/native';
import {StackNavigationProp} from '@react-navigation/stack';
import {colors, typography, spacing, borderRadius} from '../../theme';
import {RootStackParamList} from '../../types';

type WelcomeScreenNavigationProp = StackNavigationProp<
  RootStackParamList,
  'Welcome'
>;

const WelcomeScreen = () => {
  const navigation = useNavigation<WelcomeScreenNavigationProp>();

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <View style={styles.headerSection}>
          <Text style={styles.title}>ACL Rehab</Text>
          <Text style={styles.titleAccent}>Tracker</Text>
          <Text style={styles.subtitle}>
            Track your knee recovery progress with precision angle measurements
          </Text>
        </View>

        <View style={styles.illustrationContainer}>
          <View style={styles.illustration}>
            <View style={styles.kneeIcon}>
              <View style={styles.legUpper} />
              <View style={styles.kneeJoint} />
              <View style={styles.legLower} />
            </View>
          </View>
        </View>

        <View style={styles.featureList}>
          <View style={styles.featureItem}>
            <View style={styles.featureDot} />
            <Text style={styles.featureText}>
              Measure knee extension & flexion
            </Text>
          </View>
          <View style={styles.featureItem}>
            <View style={styles.featureDot} />
            <Text style={styles.featureText}>
              Track progress week over week
            </Text>
          </View>
          <View style={styles.featureItem}>
            <View style={styles.featureDot} />
            <Text style={styles.featureText}>
              Visual proof with photo storage
            </Text>
          </View>
        </View>
      </View>

      <View style={styles.footer}>
        <TouchableOpacity
          style={styles.button}
          onPress={() => navigation.navigate('NameInput')}
          activeOpacity={0.8}>
          <Text style={styles.buttonText}>Get Started</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.xxl,
  },
  headerSection: {
    marginBottom: spacing.xl,
  },
  title: {
    ...typography.largeTitle,
    color: colors.text,
    marginBottom: 0,
  },
  titleAccent: {
    ...typography.largeTitle,
    color: colors.primary,
    marginBottom: spacing.md,
  },
  subtitle: {
    ...typography.body,
    color: colors.textSecondary,
    marginTop: spacing.sm,
  },
  illustrationContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: spacing.xl,
  },
  illustration: {
    width: 200,
    height: 200,
    backgroundColor: colors.surface,
    borderRadius: borderRadius.xl,
    justifyContent: 'center',
    alignItems: 'center',
  },
  kneeIcon: {
    alignItems: 'center',
  },
  legUpper: {
    width: 20,
    height: 60,
    backgroundColor: colors.primary,
    borderRadius: 10,
    transform: [{rotate: '-15deg'}],
  },
  kneeJoint: {
    width: 24,
    height: 24,
    backgroundColor: colors.success,
    borderRadius: 12,
    marginVertical: -8,
    zIndex: 1,
  },
  legLower: {
    width: 20,
    height: 60,
    backgroundColor: colors.primary,
    borderRadius: 10,
    transform: [{rotate: '15deg'}],
  },
  featureList: {
    marginTop: spacing.lg,
  },
  featureItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.md,
  },
  featureDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.primary,
    marginRight: spacing.md,
  },
  featureText: {
    ...typography.body,
    color: colors.text,
  },
  footer: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl,
  },
  button: {
    backgroundColor: colors.primary,
    paddingVertical: spacing.md,
    borderRadius: borderRadius.lg,
    alignItems: 'center',
  },
  buttonText: {
    ...typography.headline,
    color: colors.text,
  },
});

export default WelcomeScreen;
